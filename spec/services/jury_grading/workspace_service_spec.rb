# frozen_string_literal: true

describe JuryGrading::WorkspaceService do
  let(:course) { course_factory(active_all: true) }
  let(:teacher) { course.teachers.first }
  let(:jury_role) { custom_ta_role(described_class::ROLE_NAME, account: course.root_account) }
  let(:juror_a) { user_factory(active_all: true, name: "Jury 01") }
  let(:juror_b) { user_factory(active_all: true, name: "Jury 02") }
  let(:outsider) { user_factory(active_all: true, name: "Not Jury") }
  let(:tp) { jury_assignment("Teams Results Document Submission - TP") }
  let(:inn) { jury_assignment("Teams Results Document Submission - IN") }

  def jury_assignment(title)
    assignment = course.assignments.create!(title:, points_possible: 10, moderated_grading: true, final_grader: teacher, grader_count: 1)
    assignment.update!(jury_calibrated_grading: true)
    assignment
  end

  before do
    [juror_a, juror_b].each { |juror| course.enroll_user(juror, "TaEnrollment", role: jury_role, enrollment_state: "active") }
    course.enroll_user(outsider, "TaEnrollment", enrollment_state: "active")
  end

  it "creates one group set per selected juror for the given assignment" do
    result = described_class.new(assignment: tp).ensure!(juror_ids: [juror_a.id])

    expect(result[:created]).to eq [juror_a]
    workspaces = JuryGradingWorkspace.where(assignment: tp)
    expect(workspaces.pluck(:juror_id)).to eq [juror_a.id]
    expect(workspaces.first.group_category.groups.active.count).to eq 1
  end

  it "keeps the two assignments' rosters independent" do
    described_class.new(assignment: tp).ensure!(juror_ids: [juror_a.id])
    described_class.new(assignment: inn).ensure!(juror_ids: [juror_b.id])

    expect(JuryGrading::Scope.new(assignment: tp, user: juror_a).group).to be_present
    expect(JuryGrading::Scope.new(assignment: tp, user: juror_b).group).to be_nil
    expect(JuryGrading::Scope.new(assignment: inn, user: juror_b).group).to be_present
    expect(JuryGrading::Scope.new(assignment: inn, user: juror_a).group).to be_nil
  end

  it "lets one juror serve on several assignments with separate groups" do
    described_class.new(assignment: tp).ensure!(juror_ids: [juror_a.id])
    described_class.new(assignment: inn).ensure!(juror_ids: [juror_a.id])

    tp_group = JuryGrading::Scope.new(assignment: tp, user: juror_a).group
    in_group = JuryGrading::Scope.new(assignment: inn, user: juror_a).group

    expect(tp_group).to be_present
    expect(in_group).to be_present
    expect(tp_group.id).not_to eq in_group.id
  end

  it "allows the same team in several jurors' groups so calibration can overlap" do
    team = student_in_course(course:, active_all: true).user
    described_class.new(assignment: tp).ensure!(juror_ids: [juror_a.id, juror_b.id])

    [juror_a, juror_b].each do |juror|
      JuryGradingWorkspace.find_by(assignment: tp, juror:).group_category.groups.first.add_user(team, "accepted")
    end

    expect(JuryGrading::Scope.new(assignment: tp, user: juror_a).group.group_memberships.active.pluck(:user_id)).to eq [team.id]
    expect(JuryGrading::Scope.new(assignment: tp, user: juror_b).group.group_memberships.active.pluck(:user_id)).to eq [team.id]
  end

  it "ignores users who are not Jury in the course" do
    result = described_class.new(assignment: tp).ensure!(juror_ids: [outsider.id, teacher.id, juror_a.id])

    expect(result[:created]).to eq [juror_a]
    expect(JuryGradingWorkspace.where(assignment: tp).pluck(:juror_id)).to eq [juror_a.id]
  end

  it "is idempotent" do
    described_class.new(assignment: tp).ensure!(juror_ids: [juror_a.id])
    result = described_class.new(assignment: tp).ensure!(juror_ids: [juror_a.id])

    expect(result[:created]).to be_empty
    expect(result[:existing]).to eq [juror_a]
    expect(JuryGradingWorkspace.where(assignment: tp).count).to eq 1
  end

  it "names the group set from the assignment title by default" do
    described_class.new(assignment: tp).ensure!(juror_ids: [juror_a.id])

    expect(JuryGradingWorkspace.find_by(assignment: tp, juror: juror_a).group_category.name)
      .to eq "Teams Results Document Submission - TP — Jury 01 (#{juror_a.id})"
  end

  it "truncates a long assignment title in the group set name" do
    long = jury_assignment("A" * 80)
    described_class.new(assignment: long).ensure!(juror_ids: [juror_a.id])

    name = JuryGradingWorkspace.find_by(assignment: long, juror: juror_a).group_category.name
    expect(name).to eq "#{("A" * 80).truncate(described_class::LABEL_LIMIT)} — Jury 01 (#{juror_a.id})"
    expect(name.length).to be < 80
  end

  it "uses a supplied label instead of the title" do
    described_class.new(assignment: tp, label: "TP").ensure!(juror_ids: [juror_a.id])

    expect(JuryGradingWorkspace.find_by(assignment: tp, juror: juror_a).group_category.name)
      .to eq "TP — Jury 01 (#{juror_a.id})"
  end

  it "disambiguates when two assignments truncate to the same label" do
    first = jury_assignment("#{"T" * 45}one")
    second = jury_assignment("#{"T" * 45}two")

    described_class.new(assignment: first).ensure!(juror_ids: [juror_a.id])
    expect { described_class.new(assignment: second).ensure!(juror_ids: [juror_a.id]) }.not_to raise_error

    names = [first, second].map { |a| JuryGradingWorkspace.find_by(assignment: a, juror: juror_a).group_category.name }
    expect(names.uniq.length).to eq 2
  end

  it "caps a long supplied label so the category name stays valid" do
    described_class.new(assignment: tp, label: "L" * 500).ensure!(juror_ids: [juror_a.id])

    name = JuryGradingWorkspace.find_by(assignment: tp, juror: juror_a).group_category.name
    expect(name.length).to be <= GroupCategory.maximum_string_length
  end

  it "ignores juror_ids that are not integers" do
    result = described_class.new(assignment: tp).ensure!(juror_ids: { "0" => juror_a.id.to_s })

    expect(result[:created]).to be_empty
    expect(JuryGradingWorkspace.where(assignment: tp)).to be_empty
  end

  it "creates nothing when an empty juror list is given" do
    result = described_class.new(assignment: tp).ensure!(juror_ids: [])

    expect(result[:created]).to be_empty
  end

  it "defaults to every Jury member when no ids are given" do
    result = described_class.new(assignment: tp).ensure!

    expect(result[:created]).to match_array [juror_a, juror_b]
  end
end
