# frozen_string_literal: true

describe JuryGrading::RunService do
  it "uses Account for the root account association" do
    expect(JuryGradingRun.reflect_on_association(:root_account).class_name).to eq("Account")
  end

  it "preloads rubric assessments and submissions before reading observations" do
    provisional_grades = instance_double(ActiveRecord::Relation)
    assignment = instance_double(Assignment, provisional_grades:)
    service = described_class.new(assignment:, created_by: instance_double(User))

    expect(provisional_grades).to receive(:preload).with(:rubric_assessments, :submission).and_return([])
    allow(assignment).to receive(:rubric_association).and_return(nil)

    expect(service.send(:source_observations)).to eq([])
  end

  it "uses the immutable snapshot after results are published" do
    coverage = { completed_ratings: 18, missing: [] }
    assignment = instance_double(Assignment, published_jury_grading_run_id: 7)
    run = instance_double(JuryGradingRun, id: 7, input: { observations: [{ team: 1 }], coverage: })

    readiness = described_class.new(assignment:, created_by: instance_double(User)).readiness(run:)

    expect(readiness).to include(observations: [{ team: 1 }], coverage:, issues: [], stale: false)
  end

  it "reports missing assigned rubric ratings without making them a calculation error" do
    assignment = instance_double(Assignment)
    service = described_class.new(assignment:, created_by: instance_double(User))
    first_group = instance_double(Group)
    second_group = instance_double(Group)
    first_memberships = double
    second_memberships = double
    allow(first_group).to receive(:group_memberships).and_return(first_memberships)
    allow(second_group).to receive(:group_memberships).and_return(second_memberships)
    allow(first_memberships).to receive(:active).and_return(first_memberships)
    allow(second_memberships).to receive(:active).and_return(second_memberships)
    allow(first_memberships).to receive(:where).with(user_id: [1, 2]).and_return(first_memberships)
    allow(second_memberships).to receive(:where).with(user_id: [1, 2]).and_return(second_memberships)
    allow(first_memberships).to receive(:pluck).with(:user_id).and_return([1, 2])
    allow(second_memberships).to receive(:pluck).with(:user_id).and_return([1])
    allow(service).to receive_messages(
      team_ids: [1, 2],
      jury_groups: [[10, first_group], [20, second_group]],
      rubric_criterion_ids: %w[quality delivery],
      rubric_total_points: 10.0
    )
    allow(assignment).to receive(:points_possible).and_return(10.0)

    coverage = service.send(
      :coverage,
      [
        { team: 1, criterion: "quality", juror: 10, score: 4.0 },
        { team: 1, criterion: "delivery", juror: 10, score: 4.0 },
        { team: 2, criterion: "quality", juror: 10, score: 4.0 },
        { team: 2, criterion: "delivery", juror: 10, score: 4.0 },
        { team: 1, criterion: "quality", juror: 20, score: 4.0 }
      ]
    )

    expect(coverage.slice(:allocated_assessments, :completed_assessments, :allocated_ratings, :completed_ratings)).to eq(
      allocated_assessments: 3,
      completed_assessments: 2,
      allocated_ratings: 6,
      completed_ratings: 5
    )
    expect(coverage[:missing]).to eq([{ juror: 20, team: 1, criteria: ["delivery"] }])
    expect(service.send(:configuration_issues, coverage)).to be_empty
  end

  it "does not count the Student View test student as a team" do
    course_with_student(active_all: true)
    @course.student_view_student
    assignment = @course.assignments.create!(points_possible: 10)

    service = described_class.new(assignment:, created_by: @teacher)

    expect(service.send(:team_ids)).to eq([@student.id])
  end

  it "counts overlapping Jury pairs once across all teams" do
    service = described_class.new(assignment: instance_double(Assignment), created_by: instance_double(User))

    topology = service.send(:topology, [[10, 1], [20, 1], [10, 2], [20, 2]], [1, 2], [10, 20])

    expect(topology).to include(shared_jury_pairs: 1, possible_jury_pairs: 1)
  end

  it "marks an existing result stale when the Jury allocation changes" do
    assignment = instance_double(Assignment, published_jury_grading_run_id: nil)
    service = described_class.new(assignment:, created_by: instance_double(User))
    run = instance_double(
      JuryGradingRun,
      id: 7,
      input: { observations: [], allocations: [[10, 1]] }
    )

    allow(service).to receive_messages(
      source_observations: [],
      jury_team_allocations: [[10, 2]],
      coverage: { distribution: { allocated: { shared_jury_pairs: 1 } } },
      workspace_issues: [],
      configuration_issues: []
    )

    expect(service.readiness(run:)[:stale]).to be(true)
  end
end
