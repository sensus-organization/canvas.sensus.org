# frozen_string_literal: true

class JuryGradingWorkspace < ActiveRecord::Base
  extend RootAccountResolver

  resolves_root_account through: :course
  belongs_to :course
  belongs_to :juror, class_name: "User"
  belongs_to :group_category

  validates :course, :juror, :group_category, :root_account_id, presence: true
  validates :juror_id, uniqueness: { scope: :course_id }
  validates :group_category_id, uniqueness: true
end
