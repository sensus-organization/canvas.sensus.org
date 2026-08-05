# frozen_string_literal: true

describe JuryGrading::Scope do
  let(:course) { course_factory(active_all: true) }
  let(:teacher) { course.teachers.first }
  let(:jury_role) { custom_ta_role(JuryGrading::WorkspaceService::ROLE_NAME, account: course.root_account) }
  let(:juror) { user_factory(active_all: true) }
  let(:team) { student_in_course(course:, active_all: true).user }
  let(:ordinary) { course.assignments.create!(title: "Ordinary", points_possible: 10) }

  def jury_assignment
    assignment = course.assignments.create!(title: "Jury", points_possible: 10, moderated_grading: true, final_grader: teacher, grader_count: 1)
    assignment.update!(jury_calibrated_grading: true)
    assignment
  end

  def allocate!(user)
    JuryGradingWorkspace.find_by(course:, juror:).group_category.groups.first.add_user(user, "accepted")
  end

  before do
    course.enroll_user(juror, "TaEnrollment", role: jury_role, enrollment_state: "active")
    JuryGrading::WorkspaceService.new(course:).ensure!
  end

  context "on a jury-calibrated assignment" do
    it "treats a Jury member as a juror who may grade their allocated teams" do
      allocate!(team)
      assignment = jury_assignment
      assignment.submit_homework(team, body: "done", submission_type: "online_text_entry")
      scope = described_class.new(assignment:, user: juror)

      expect(scope.jury_user?).to be true
      expect(scope.jury_assignment?).to be true
      expect(scope.grading_open?).to be true
      expect(scope.permits_submission?(assignment.submissions.find_by(user: team))).to be true
    end
  end

  context "on an assignment that is not jury-calibrated" do
    it "still recognises the Jury member by their enrollment" do
      expect(described_class.new(assignment: ordinary, user: juror).jury_user?).to be true
    end

    it "closes grading for them" do
      scope = described_class.new(assignment: ordinary, user: juror)

      expect(scope.jury_assignment?).to be false
      expect(scope.jury?).to be false
      expect(scope.grading_open?).to be false
    end

    it "refuses a submission even when the team is allocated to them" do
      allocate!(team)
      ordinary.submit_homework(team, body: "done", submission_type: "online_text_entry")
      scope = described_class.new(assignment: ordinary, user: juror)

      expect(scope.permits_submission?(ordinary.submissions.find_by(user: team))).to be false
    end
  end

  context "for a grader who is not Jury" do
    it "leaves every assignment ungated" do
      ordinary.submit_homework(team, body: "done", submission_type: "online_text_entry")
      scope = described_class.new(assignment: ordinary, user: teacher)

      expect(scope.jury_user?).to be false
      expect(scope.jury_assignment?).to be false
      expect(scope.permits_submission?(ordinary.submissions.find_by(user: team))).to be true
    end
  end
end
