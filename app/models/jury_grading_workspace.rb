# frozen_string_literal: true

class JuryGradingWorkspace < ActiveRecord::Base
  extend RootAccountResolver

  resolves_root_account through: :course
  belongs_to :course
  belongs_to :assignment, class_name: "AbstractAssignment"
  belongs_to :juror, class_name: "User"
  belongs_to :group_category

  validates :course, :assignment, :juror, :group_category, :root_account_id, presence: true
  validates :juror_id, uniqueness: { scope: :assignment_id }
  validates :group_category_id, uniqueness: true
end
