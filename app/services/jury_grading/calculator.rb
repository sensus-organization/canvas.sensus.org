# frozen_string_literal: true

module JuryGrading
  class Calculator
    DEFAULT_SETTINGS = { team: 1.0, criterion: 1.0, severity: 1.0, scale_use: 5.0, bootstrap: 1000, seed: 2026 }.freeze
    NORMALIZED_POINTS = 5.0

    def initialize(observations:, settings: {}, progress: nil)
      @observations = observations.map { |row| row.symbolize_keys.slice(:team, :criterion, :juror, :score, :criterion_points, :comments) }
      @settings = DEFAULT_SETTINGS.merge(settings.symbolize_keys)
      @progress = progress
      @criterion_points = @observations.each_with_object({}) do |row, points|
        points[row[:criterion]] ||= row[:criterion_points]
      end
      validate_observations!
      @normalized_observations = @observations.map do |row|
        row.merge(score: normalized_score(row))
      end
    end

    def calculate
      raise ArgumentError, "Jury results need rubric observations" if @observations.empty?

      report_progress(0.0)
      fit = fit_model(@normalized_observations)
      report_progress(0.1)
      team_ids = @normalized_observations.pluck(:team).uniq
      team_rows = @normalized_observations.group_by { |row| row[:team] }
      juror_rows = @normalized_observations.group_by { |row| row[:juror] }
      raw = team_rows.transform_values { |rows| average(rows.pluck(:score)) }
      adjusted_normalized = team_ids.index_with { |team| fit[:mean] + fit[:team][team] }
      adjusted = adjusted_normalized.transform_values { |score| canvas_score(score) }
      ranks = adjusted_normalized.sort_by { |_team, score| -score }.each_with_index.to_h { |(team, _score), index| [team, index + 1] }
      bootstrap = bootstrap_ranks(team_ids, fit)
      shared_teams = team_rows.select { |_team, rows| rows.pluck(:juror).uniq.length > 1 }.keys

      result_warnings = warnings(fit, adjusted_normalized)
      {
        teams: team_ids.index_with do |team|
          {
            raw_average: raw[team],
            observation_count: team_rows[team].length,
            score_standard_deviation: standard_deviation(team_rows[team].pluck(:score)),
            model_effect: fit[:team][team],
            adjusted_score: adjusted[team],
            adjusted_normalized_score: adjusted_normalized[team],
            score_scale: points_possible,
            adjusted_rank: ranks[team],
            top_1_probability: bootstrap[team][:top_1],
            top_3_probability: bootstrap[team][:top_3],
            top_5_probability: bootstrap[team][:top_5]
          }
        end,
        ratings: @observations.group_by { |row| row[:team] }.transform_values do |rows|
          rows.map do |row|
            row.slice(:juror, :criterion, :score, :criterion_points, :comments).merge(raw_score: row[:score], normalized_score: normalized_score(row))
          end
        end,
        warnings: result_warnings,
        blocking_warnings: result_warnings & ["non-positive effective juror slope", "disconnected jury graph"],
        model: { overall_mean: fit[:mean], criterion_effects: fit[:criterion], normalized_score_scale: NORMALIZED_POINTS, score_scale: points_possible },
        jurors: juror_rows.transform_values do |rows|
          teams = rows.pluck(:team)
          residuals = rows.map { |row| row[:score] - predict(row, fit) }
          juror = rows.first[:juror]
          {
            effective_slope: fit[:slope][juror],
            score_bias: fit[:severity][juror],
            observation_count: rows.length,
            shared_team_count: (teams & shared_teams).length,
            raw_average: average(rows.pluck(:score)),
            residual_rmse: Math.sqrt(average(residuals.map { |value| value * value })),
            mean_absolute_residual: average(residuals.map(&:abs))
          }
        end
      }
    end

    private

    def validate_observations!
      @observations.each do |row|
        points = row[:criterion_points]
        raise ArgumentError, "Jury rubric observations need criterion_points" unless points.to_f.positive?
        raise ArgumentError, "Jury rubric scores must be within their criterion scale" unless row[:score].to_f.between?(0, points.to_f)
        raise ArgumentError, "Jury rubric criterion scales must be consistent" unless (@criterion_points[row[:criterion]].to_f - points.to_f).abs < Float::EPSILON
      end
    end

    def normalized_score(row)
      row[:score].to_f / row[:criterion_points].to_f * NORMALIZED_POINTS
    end

    def points_possible
      @criterion_points.values.sum(&:to_f)
    end

    def canvas_score(score)
      score.clamp(0.0, NORMALIZED_POINTS) / NORMALIZED_POINTS * points_possible
    end

    def report_progress(value)
      @progress&.call(value)
    end

    def fit_model(rows, initial: nil)
      teams = rows.pluck(:team).uniq
      criteria = rows.pluck(:criterion).uniq
      jurors = rows.pluck(:juror).uniq
      params = initial_parameters(initial, rows, teams, criteria, jurors)
      active_row_indexes = {
        criterion: rows.each_index.group_by { |index| rows[index][:criterion] },
        severity: rows.each_index.group_by { |index| rows[index][:juror] },
        team: rows.each_index.group_by { |index| rows[index][:team] },
        slope: rows.each_index.group_by { |index| rows[index][:juror] }
      }

      12.times do
        previous = copy_params(params)
        params = ridge(rows, params, :team_effect, active_row_indexes)
        params = ridge(rows, params, :slope_effect, active_row_indexes)
        break if maximum_change(params, previous) < 1e-6
      end
      params
    end

    def ridge(rows, params, mode, active_row_indexes)
      coefficients = coefficient_keys(params, mode)
      prediction = rows.map { |row| predict(row, params) }
      residual = rows.each_with_index.map { |row, index| row[:score].to_f - prediction[index] }

      40.times do
        maximum_change = 0.0
        coefficients.each do |key, id, penalty|
          indices = active_row_indexes.fetch(key).fetch(id, [])
          next if indices.empty?

          values = indices.map { |index| feature(rows[index], params, key) }
          old = value(params, key, id)
          indices.each_with_index { |index, position| residual[index] += values[position] * old }
          updated = indices.each_with_index.sum { |index, position| values[position] * residual[index] } / (values.sum { |v| v * v } + penalty)
          maximum_change = [maximum_change, (updated - old).abs].max
          set_value(params, key, id, updated)
          indices.each_with_index { |index, position| residual[index] -= values[position] * updated }
        end

        mean_shift = residual.sum / residual.length.to_f
        params[:mean] += mean_shift
        residual.map! { |value| value - mean_shift }
        break if [maximum_change, mean_shift.abs].max < 1e-6
      end
      params
    end

    def initial_parameters(initial, rows, teams, criteria, jurors)
      unless initial
        return {
          mean: rows.pluck(:score).sum / rows.length.to_f,
          team: teams.index_with { 0.0 },
          criterion: criteria.index_with { 0.0 },
          severity: jurors.index_with { 0.0 },
          slope: jurors.index_with { 1.0 }
        }
      end

      {
        mean: initial[:mean],
        team: teams.index_with { |id| initial[:team].fetch(id, 0.0) },
        criterion: criteria.index_with { |id| initial[:criterion].fetch(id, 0.0) },
        severity: jurors.index_with { |id| initial[:severity].fetch(id, 0.0) },
        slope: jurors.index_with { |id| initial[:slope].fetch(id, 1.0) }
      }
    end

    def copy_params(params)
      params.transform_values { |value| value.is_a?(Hash) ? value.dup : value }
    end

    def maximum_change(params, previous)
      params.reduce(0.0) do |change, (key, value)|
        differences = if value.is_a?(Hash)
                        value.map { |id, coefficient| (coefficient - previous[key][id]).abs }
                      else
                        [(value - previous[key]).abs]
                      end
        [change, differences.max].max
      end
    end

    def coefficient_keys(params, mode)
      keys = params[:criterion].keys.map { |id| [:criterion, id, @settings[:criterion]] } + params[:severity].keys.map { |id| [:severity, id, @settings[:severity]] }
      keys += if mode == :team_effect
                params[:team].keys.map { |id| [:team, id, @settings[:team]] }
              else
                params[:slope].keys.map { |id| [:slope, id, @settings[:scale_use]] }
              end
      keys
    end

    def feature(row, params, key)
      case key
      when :team then params[:slope][row[:juror]]
      when :slope then params[:team][row[:team]]
      else 1.0
      end
    end

    def value(params, key, id)
      (key == :slope) ? params[:slope][id] - 1.0 : params.fetch(key).fetch(id)
    end

    def set_value(params, key, id, value)
      params[:slope][id] = value + 1.0 if key == :slope
      params[key][id] = value unless key == :slope
    end

    def predict(row, params)
      params[:mean] + params[:criterion][row[:criterion]] + params[:severity][row[:juror]] + (params[:team][row[:team]] * params[:slope][row[:juror]])
    end

    def average(values)
      values.sum / values.length.to_f
    end

    def standard_deviation(values)
      mean = average(values)
      Math.sqrt(average(values.map { |value| (value - mean)**2 }))
    end

    def bootstrap_ranks(team_ids, initial_fit)
      random = Random.new(@settings[:seed])
      grouped = @normalized_observations.group_by { |row| row[:team] }.transform_values do |rows|
        rows.group_by { |row| row[:juror] }.values
      end
      counts = team_ids.index_with { { top_1: 0, top_3: 0, top_5: 0 } }
      @settings[:bootstrap].times do |bootstrap_index|
        sample = team_ids.flat_map do |team|
          team_groups = grouped.fetch(team)
          Array.new(team_groups.length) { team_groups[random.rand(team_groups.length)] }
        end.flatten
        fitted = fit_model(sample, initial: initial_fit)
        result = team_ids.sort_by { |team| -(fitted[:mean] + fitted[:team].fetch(team, 0.0)) }
        result.each_with_index do |team, rank|
          counts[team][:top_1] += 1 if rank.zero?
          counts[team][:top_3] += 1 if rank < 3
          counts[team][:top_5] += 1 if rank < 5
        end
        report_progress(0.1 + (0.9 * (bootstrap_index + 1) / @settings[:bootstrap]))
      end
      counts.transform_values { |count| count.transform_values { |value| value / @settings[:bootstrap].to_f } }
    end

    def warnings(fit, adjusted)
      warnings = []
      warnings << "non-positive effective juror slope" if fit[:slope].values.any? { |slope| slope <= 0 }
      warnings << "disconnected jury graph" unless connected?
      leaders = adjusted.values.sort.last(2).reverse
      warnings << "close top cluster" if leaders.length == 2 && leaders[0] - leaders[1] < 0.05
      warnings
    end

    def connected?
      seen_teams = Set.new([@observations.first[:team]])
      seen_jurors = Set.new
      loop do
        before = seen_teams.size + seen_jurors.size
        @observations.each do |row|
          seen_jurors << row[:juror] if seen_teams.include?(row[:team])
          seen_teams << row[:team] if seen_jurors.include?(row[:juror])
        end
        break if before == seen_teams.size + seen_jurors.size
      end
      seen_teams.size == @observations.pluck(:team).uniq.size && seen_jurors.size == @observations.pluck(:juror).uniq.size
    end
  end
end
