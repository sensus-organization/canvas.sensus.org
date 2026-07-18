# frozen_string_literal: true

class JuryGradingRun < ActiveRecord::Base
  belongs_to :assignment, class_name: "AbstractAssignment", inverse_of: :jury_grading_runs
  belongs_to :created_by, class_name: "User"
  belongs_to :root_account, class_name: "Account"

  validates :algorithm_version, :workflow_state, presence: true
  scope :completed, -> { where(workflow_state: "completed") }

  def progress_tag
    "jury_grading_run:#{global_id}"
  end

  def progress
    return unless assignment

    Progress.where(context: assignment, tag: progress_tag).order(:created_at).last
  end

  def calculate!(progress = nil)
    update!(workflow_state: "running")
    update_progress = lambda do |fraction|
      completion = (fraction * 100).round
      progress.update_completion!(completion) if progress && completion > progress.completion.to_i
    end
    update!(
      results: JuryGrading::Calculator.new(observations: input.with_indifferent_access.fetch(:observations), settings:, progress: update_progress).calculate,
      workflow_state: "completed"
    )
  rescue => e
    update!(workflow_state: "failed", results: { error: e.message })
    raise
  end
end
