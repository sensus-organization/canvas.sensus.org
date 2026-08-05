# frozen_string_literal: true

module JuryGrading
  class RunService
    ALGORITHM_VERSION = "random_slope_ridge_v1"

    def initialize(assignment:, created_by:, settings: {})
      @assignment = assignment
      @created_by = created_by
      @settings = settings
    end

    def enqueue!
      readiness = readiness()
      validate!(readiness)
      run = @assignment.jury_grading_runs.create!(
        created_by: @created_by,
        root_account: @assignment.root_account,
        algorithm_version: ALGORITHM_VERSION,
        settings: Calculator::DEFAULT_SETTINGS.merge(@settings),
        input: { observations: readiness[:observations], coverage: readiness[:coverage], allocations: readiness[:allocations] },
        workflow_state: "queued"
      )
      Progress.create!(context: @assignment, user: @created_by, tag: run.progress_tag, completion: 0)
              .process_job(run, :calculate!, { priority: Delayed::LOW_PRIORITY, strand: "JuryGradingRun:#{run.global_id}" })
      run
    end

    def readiness(run: nil)
      return snapshot_readiness(run) if run && @assignment.published_jury_grading_run_id == run.id

      observations = source_observations
      allocations = jury_team_allocations
      coverage = coverage(observations, allocations:)
      {
        observations:,
        allocations:,
        coverage:,
        issues: workspace_issues + configuration_issues(coverage),
        stale: run.present? && (
          canonical_observations(observations) != canonical_observations(run.input.with_indifferent_access.fetch(:observations)) ||
          canonical_allocations(allocations) != canonical_allocations(run.input.with_indifferent_access.fetch(:allocations, []))
        )
      }
    end

    private

    def source_observations
      @assignment.provisional_grades.preload(:rubric_assessments, :submission).filter_map do |grade|
        scope = jury_scopes[grade.scorer_id]
        next unless scope&.permits_submission?(grade.submission)

        grade.rubric_assessments.flat_map do |assessment|
          (assessment.data || []).filter_map do |rating|
            rating = rating.with_indifferent_access
            criterion_points = rubric_criteria[rating[:criterion_id].to_s]
            next if rating[:points].blank? || criterion_points.blank?

            { team: grade.submission.user_id, criterion: rating[:criterion_id].to_s, juror: grade.scorer_id, score: rating[:points], criterion_points:, comments: rating[:comments].presence, assessment_id: assessment.id }
          end
        end
      end.flatten
    end

    def snapshot_readiness(run)
      input = run.input.with_indifferent_access
      observations = input.fetch(:observations, [])
      {
        observations:,
        allocations: input[:allocations] || [],
        coverage: input[:coverage]&.with_indifferent_access || coverage(observations),
        issues: [],
        stale: false
      }
    end

    def validate!(readiness)
      raise ArgumentError, readiness[:issues].join(". ") if readiness[:issues].present?
    end

    def workspace_issues
      jury_ids = @assignment.context.all_enrollments.active.joins(:role)
                            .where(enrollments: { type: "TaEnrollment" }, roles: { name: WorkspaceService::ROLE_NAME })
                            .distinct.pluck(:user_id)
      return ["No active Jury users"] if jury_ids.empty?

      jury_ids.filter_map do |jury_id|
        scope = Scope.new(assignment: @assignment, user: User.find(jury_id))
        "Jury workspace is missing or malformed for user #{jury_id}" unless scope.group
      end
    end

    def configuration_issues(coverage)
      issues = []
      issues << "Assignment needs an attached grading rubric" if coverage[:criterion_ids].empty?
      if coverage[:criterion_ids].present? && (rubric_total_points - @assignment.points_possible.to_f).abs > 0.001
        issues << "Scoring rubric total (#{rubric_total_points}) must equal assignment points (#{@assignment.points_possible})"
      end
      issues << "No jury-team overlap" if coverage[:distribution][:allocated][:shared_jury_pairs].zero?
      issues << "Teams without a Jury allocation: #{coverage[:unallocated_team_ids].join(", ")}" if coverage[:unallocated_team_ids].present?
      issues << "No rubric observations" if coverage[:completed_ratings].zero?
      issues
    end

    def coverage(observations, allocations: jury_team_allocations)
      criteria = rubric_criterion_ids
      teams = team_ids
      jurors = jury_groups.map(&:first)
      observed = observations.to_set { |row| [row[:juror], row[:team], row[:criterion].to_s] }
      missing = allocations.filter_map do |jury_id, team_id|
        missing_criteria = criteria.reject { |criterion_id| observed.include?([jury_id, team_id, criterion_id]) }
        { juror: jury_id, team: team_id, criteria: missing_criteria } if missing_criteria.present?
      end
      observed_pairs = observations.map { |row| [row[:juror], row[:team]] }.uniq
      allocated_to = allocations.group_by(&:last).transform_values { |pairs| pairs.map(&:first) }
      {
        team_count: teams.length,
        criterion_ids: criteria,
        allocated_assessments: allocations.length,
        completed_assessments: allocations.length - missing.length,
        allocated_ratings: allocations.length * criteria.length,
        completed_ratings: allocations.sum { |jury_id, team_id| criteria.count { |criterion_id| observed.include?([jury_id, team_id, criterion_id]) } },
        missing:,
        unallocated_team_ids: teams - allocated_to.keys,
        ungraded_team_ids: teams - observations.pluck(:team).uniq,
        distribution: {
          allocated: topology(allocations, teams, jurors),
          completed: topology(observed_pairs, teams, jurors)
        }
      }
    end

    def jury_groups
      @jury_groups ||= jury_scopes.map { |jury_id, scope| [jury_id, scope.group] }
    end

    def team_ids
      @team_ids ||= @assignment.context.student_enrollments.active.not_fake.distinct.pluck(:user_id)
    end

    def rubric_criterion_ids
      rubric_criteria.keys
    end

    def topology(pairs, teams, jurors)
      team_counts = teams.index_with { |team_id| pairs.count { |_jury_id, assigned_team_id| assigned_team_id == team_id } }
      shared_jury_pairs = pairs.group_by(&:last).values.flat_map do |team_pairs|
        team_pairs.map(&:first).combination(2).map(&:sort)
      end.uniq.length
      {
        teams_with_multiple_jurors: team_counts.count { |_team_id, count| count > 1 },
        team_jury_count_min: team_counts.values.min || 0,
        team_jury_count_median: median(team_counts.values),
        team_jury_count_max: team_counts.values.max || 0,
        shared_jury_pairs:,
        possible_jury_pairs: jurors.length * (jurors.length - 1) / 2,
        connected: connected?(pairs, teams, jurors)
      }
    end

    def connected?(pairs, teams, jurors)
      return false if teams.empty? || jurors.empty?

      seen_teams = Set.new([teams.first])
      seen_jurors = Set.new
      loop do
        size = seen_teams.size + seen_jurors.size
        pairs.each do |jury_id, team_id|
          seen_jurors << jury_id if seen_teams.include?(team_id)
          seen_teams << team_id if seen_jurors.include?(jury_id)
        end
        break if size == seen_teams.size + seen_jurors.size
      end
      seen_teams.size == teams.size && seen_jurors.size == jurors.size
    end

    def median(values)
      return 0 if values.empty?

      ordered = values.sort
      middle = ordered.length / 2
      ordered.length.odd? ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2.0
    end

    def canonical_observations(observations)
      observations.map { |row| row.with_indifferent_access.slice(:team, :criterion, :juror, :score, :criterion_points) }
                  .sort_by { |row| [row[:team], row[:criterion].to_s, row[:juror], row[:score], row[:criterion_points]] }
    end

    def active_jury_ids
      @active_jury_ids ||= @assignment.context.all_enrollments.active.joins(:role)
                                      .where(enrollments: { type: "TaEnrollment" }, roles: { name: WorkspaceService::ROLE_NAME })
                                      .distinct.pluck(:user_id)
    end

    def jury_scopes
      @jury_scopes ||= active_jury_ids.filter_map do |jury_id|
        scope = Scope.new(assignment: @assignment, user: User.find(jury_id))
        [jury_id, scope] if scope.group
      end.to_h
    end

    def jury_team_allocations
      @jury_team_allocations ||= jury_groups.flat_map do |jury_id, group|
        group.group_memberships.active.where(user_id: team_ids).pluck(:user_id).map { |team_id| [jury_id, team_id] }
      end.uniq
    end

    def rubric_criteria
      @rubric_criteria ||= Array(@assignment.rubric_association&.rubric&.data).filter_map do |criterion|
        criterion = criterion.with_indifferent_access
        id = criterion[:id]&.to_s
        points = criterion[:points].to_f
        [id, points] if id.present? && points.positive?
      end.to_h
    end

    def rubric_total_points
      rubric_criteria.values.sum
    end

    def canonical_allocations(allocations)
      allocations.map { |jury_id, team_id| [jury_id.to_i, team_id.to_i] }.sort
    end
  end
end
