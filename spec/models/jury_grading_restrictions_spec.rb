# frozen_string_literal: true

describe "Jury grading restrictions" do
  let(:course) { course_factory(active_all: true) }
  let(:teacher) { course.teachers.first }
  let(:jury_role) { custom_ta_role(JuryGrading::WorkspaceService::ROLE_NAME, account: course.root_account) }
  let(:juror) { user_factory(active_all: true) }
  let(:plain_ta) { user_factory(active_all: true) }
  let(:team) { student_in_course(course:, active_all: true).user }

  let(:jury_assignment) do
    assignment = course.assignments.create!(title: "Jury", points_possible: 10, moderated_grading: true, final_grader: teacher, grader_count: 1)
    assignment.update!(jury_calibrated_grading: true)
    assignment
  end
  let(:ordinary) { course.assignments.create!(title: "Ordinary", points_possible: 10, submission_types: "online_text_entry") }

  before do
    course.enroll_user(juror, "TaEnrollment", role: jury_role, enrollment_state: "active")
    course.enroll_user(plain_ta, "TaEnrollment", enrollment_state: "active")
  end

  describe "Course#jury_grader?" do
    it "is true only for a Jury-role enrollment" do
      expect(course.jury_grader?(juror)).to be true
      expect(course.jury_grader?(teacher)).to be false
      expect(course.jury_grader?(plain_ta)).to be false
      expect(course.jury_grader?(team)).to be false
      expect(course.jury_grader?(nil)).to be false
    end
  end

  describe "the :grade permission" do
    it "is withheld from Jury on an assignment that is not jury-calibrated" do
      expect(ordinary.grants_right?(juror, :grade)).to be false
      expect(jury_assignment.grants_right?(juror, :grade)).to be true
    end

    it "is untouched for teachers and ordinary TAs" do
      expect(ordinary.grants_right?(teacher, :grade)).to be true
      expect(jury_assignment.grants_right?(teacher, :grade)).to be true
      expect(ordinary.grants_right?(plain_ta, :grade)).to be true
    end

    it "still lets Jury attach comment files, which rides a separate grant" do
      expect(ordinary.grants_right?(juror, :attach_submission_comment_files)).to be true
    end
  end

  describe "rubric use_for_grading" do
    let(:rubric) { rubric_model(context: course, data: larger_rubric_data) }

    def assess!(assignment, association)
      submission = assignment.submit_homework(team, body: "done", submission_type: "online_text_entry")
      provisional = submission.find_or_create_provisional_grade!(juror)
      association.assess(
        user: team,
        assessor: juror,
        artifact: provisional,
        assessment: { assessment_type: "grading", criterion_crit1: { points: 3 } }
      )
      provisional.reload
    end

    it "is forced on when a rubric is associated with a jury-calibrated assignment" do
      association = rubric.associate_with(jury_assignment, course, purpose: "grading", use_for_grading: false)

      expect(association.reload.use_for_grading).to be true
    end

    it "is left alone for an ordinary assignment" do
      association = rubric.associate_with(ordinary, course, purpose: "grading", use_for_grading: false)

      expect(association.reload.use_for_grading).to be false
    end

    it "scores the provisional grade even when the stored flag is still false" do
      assignment = jury_assignment
      association = rubric.associate_with(assignment, course, purpose: "grading", use_for_grading: true)
      association.update_column(:use_for_grading, false)

      expect(assess!(assignment, association.reload).score).to eq 3
    end
  end

  describe "the gradebook importer" do
    def gradeable_for?(user)
      importer = GradebookImporter.new(GradebookUpload.new(course:, user:, progress: Progress.new), "", user, nil)
      importer.instance_variable_set(:@all_assignments, { ordinary.id => ordinary })
      importer.send(:gradeable?, submission: ordinary.submissions.find_by(user: team))
    end

    before { ordinary.submit_homework(team, body: "done", submission_type: "online_text_entry") }

    it "refuses to mark a non-jury assignment gradeable for a Jury member" do
      expect(gradeable_for?(juror)).to be false
    end

    it "still marks it gradeable for a teacher" do
      expect(gradeable_for?(teacher)).to be true
    end
  end

  describe "the grading to-do list" do
    before do
      ordinary.submit_homework(team, body: "done", submission_type: "online_text_entry")
      jury_assignment.submit_homework(team, body: "done", submission_type: "online_text_entry")
    end

    it "drops assignments a Jury member is not allowed to grade" do
      expect(juror.assignments_needing_grading(scope_only: true).to_a.map(&:title)).not_to include("Ordinary")
    end

    it "leaves teachers and ordinary TAs seeing exactly what they saw before" do
      expect(teacher.assignments_needing_grading(scope_only: true).to_a.map(&:title)).to include("Ordinary")
      expect(plain_ta.assignments_needing_grading(scope_only: true).to_a.map(&:title)).to include("Ordinary")
    end

    it "keeps jury-calibrated assignments in the scope for a Jury member" do
      sql = juror.assignments_needing_grading(scope_only: true).to_sql

      expect(sql).to include("assignments.jury_calibrated_grading")
    end
  end
end
