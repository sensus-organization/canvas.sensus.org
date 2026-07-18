# frozen_string_literal: true

class JuryGradingController < ApplicationController
  before_action :load_assignment
  before_action :require_jury_manager

  def show
    run = @assignment.published_jury_grading_run || @assignment.jury_grading_runs.order(:created_at).last
    render json: (run ? run_json(run) : {}).merge(readiness: readiness_json(run:))
  end

  def calculate
    run = @assignment.with_lock do
      @assignment.reload
      break :published if @assignment.grades_published? || @assignment.published_jury_grading_run_id.present?

      service = JuryGrading::RunService.new(assignment: @assignment, created_by: @current_user)
      @assignment.jury_grading_runs.where(workflow_state: %w[queued running]).order(:created_at).last || service.enqueue!
    end
    return render json: { message: "Jury results have already been published" }, status: :unprocessable_content if run == :published

    render json: run_json(run).merge(readiness: readiness_json(run:)), status: :accepted
  rescue ArgumentError => e
    render json: { message: e.message }, status: :unprocessable_content
  end

  def publish
    outcome = @assignment.with_lock do
      @assignment.reload
      break [:error, "Jury results have already been published"] if @assignment.grades_published? || @assignment.published_jury_grading_run_id.present?

      run = @assignment.jury_grading_runs.completed.find(params[:run_id])
      results = run.results.with_indifferent_access
      break [:error, "Jury results contain blocking warnings"] if results[:blocking_warnings].present?

      readiness = JuryGrading::RunService.new(assignment: @assignment, created_by: @current_user).readiness(run:)
      break [:error, "Cannot publish: #{readiness[:issues].join(". ")}"] if readiness[:issues].present?
      break [:error, "Jury ratings changed; calculate fresh results before publishing"] if readiness[:stale]
      if readiness[:coverage][:ungraded_team_ids].present?
        break [:error, "Cannot publish: teams without any Jury rating: #{readiness[:coverage][:ungraded_team_ids].join(", ")}"]
      end

      team_ids = results.fetch(:teams).keys
      results.fetch(:teams).each do |team_id, result|
        @assignment.grade_student(
          User.find(team_id),
          score: result.with_indifferent_access.fetch(:adjusted_score),
          grader: @current_user,
          grade_posting_in_progress: true,
          skip_grade_calc: true
        )
      end
      @assignment.update!(published_jury_grading_run: run, grades_published_at: Time.zone.now)
      [:ok, team_ids]
    end
    return render json: { message: outcome.last }, status: :unprocessable_content if outcome.first == :error

    @context.recompute_student_scores(outcome.last)
    head :no_content
  end

  private

  def load_assignment
    @context = api_find(Course, params[:course_id])
    @assignment = api_find(@context.assignments, params[:assignment_id])
  end

  def require_jury_manager
    return render_unauthorized_action if @assignment.jury_user?(@current_user)
    return if @assignment.jury_calibrated_grading? && @context.grants_right?(@current_user, :select_final_grade)

    render_unauthorized_action
  end

  def run_json(run)
    json = run.as_json(only: %i[id created_at workflow_state algorithm_version settings results])
    json = json.fetch(run.model_name.element, json)
    results = json["results"] || {}
    user_ids = results.fetch("teams", {}).keys + results.fetch("jurors", {}).keys
    json["user_names"] = user_names(user_ids)
    json["criterion_names"] = criterion_names
    if (progress = run.progress)
      progress_json = progress.as_json(only: %i[id completion workflow_state message])
      json["progress"] = progress_json.fetch(progress.model_name.element, progress_json)
    end
    json
  end

  def readiness_json(run:)
    readiness = JuryGrading::RunService.new(assignment: @assignment, created_by: @current_user).readiness(run:)
    coverage = readiness[:coverage]
    user_ids = coverage[:missing].flat_map { |row| row.values_at(:juror, :team) } + coverage[:unallocated_team_ids] + coverage[:ungraded_team_ids]
    readiness.merge(user_names: user_names(user_ids), criterion_names:)
  end

  def user_names(ids)
    User.where(id: ids).pluck(:id, :name).to_h.transform_keys(&:to_s)
  end

  def criterion_names
    Array(@assignment&.rubric_association&.rubric&.data).to_h do |criterion|
      criterion = criterion.with_indifferent_access
      [criterion[:id].to_s, criterion[:description]]
    end
  end
end
