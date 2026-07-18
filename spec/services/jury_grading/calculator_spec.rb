# frozen_string_literal: true

describe JuryGrading::Calculator do
  let(:observations) do
    [
      { team: 1, criterion: "demo", juror: 10, score: 4.0, criterion_points: 5.0 },
      { team: 2, criterion: "demo", juror: 10, score: 2.0, criterion_points: 5.0 },
      { team: 1, criterion: "demo", juror: 20, score: 5.0, criterion_points: 5.0 },
      { team: 2, criterion: "demo", juror: 20, score: 3.0, criterion_points: 5.0 }
    ]
  end

  it "returns adjusted scores, ranks, and bootstrap probabilities" do
    results = described_class.new(observations:, settings: { bootstrap: 10 }).calculate

    expect(results[:teams].keys).to contain_exactly(1, 2)
    expect(results[:teams][1][:adjusted_rank]).to eq(1)
    expect(results[:teams][1]).to include(:observation_count, :score_standard_deviation, :model_effect)
    expect(results[:ratings][1]).to include(hash_including(juror: 10, criterion: "demo", score: 4.0, criterion_points: 5.0, normalized_score: 4.0))
    expect(results[:teams][1][:top_1_probability]).to be_between(0.0, 1.0)
    expect(results[:model]).to include(:overall_mean, :criterion_effects)
    expect(results[:jurors][10]).to include(:effective_slope, :score_bias, :observation_count, :shared_team_count, :residual_rmse, :mean_absolute_residual)
    expect(results[:warnings]).not_to include("disconnected jury graph")
  end

  it "warns when jury subsets cannot calibrate each other" do
    disconnected = [observations[0], observations[3]]

    results = described_class.new(observations: disconnected, settings: { bootstrap: 2 }).calculate

    expect(results[:blocking_warnings]).to include("disconnected jury graph")
  end

  it "returns identical bootstrap probabilities for a fixed seed" do
    settings = { bootstrap: 20, seed: 42 }

    first = described_class.new(observations:, settings:).calculate
    second = described_class.new(observations:, settings:).calculate

    expect(first[:teams]).to eq(second[:teams])
  end

  it "normalizes mixed rubric scales and maps the final score to rubric points" do
    mixed_scales = [
      { team: 1, criterion: "small", juror: 10, score: 5.0, criterion_points: 5.0 },
      { team: 1, criterion: "large", juror: 10, score: 10.0, criterion_points: 10.0 },
      { team: 2, criterion: "small", juror: 10, score: 0.0, criterion_points: 5.0 },
      { team: 2, criterion: "large", juror: 10, score: 0.0, criterion_points: 10.0 }
    ]

    results = described_class.new(observations: mixed_scales, settings: { bootstrap: 2 }).calculate

    expect(results[:teams][1]).to include(raw_average: 5.0, score_scale: 15.0)
    expect(results[:teams][1][:adjusted_score]).to be_within(0.001).of(results[:teams][1][:adjusted_normalized_score].clamp(0.0, 5.0) * 3)
    expect(results[:ratings][1]).to include(hash_including(criterion: "large", score: 10.0, criterion_points: 10.0, normalized_score: 5.0))
  end

  it "keeps every team represented in each bootstrap sample" do
    one_block_per_team = [
      { team: 1, criterion: "demo", juror: 10, score: 5.0, criterion_points: 5.0 },
      { team: 2, criterion: "demo", juror: 20, score: 0.0, criterion_points: 5.0 }
    ]

    results = described_class.new(observations: one_block_per_team, settings: { bootstrap: 20, seed: 42 }).calculate

    expect(results[:teams][1][:top_1_probability]).to eq(1.0)
    expect(results[:teams][2][:top_1_probability]).to eq(0.0)
  end

  it "requires a positive, consistent rubric scale for every criterion" do
    expect do
      described_class.new(observations: [{ team: 1, criterion: "demo", juror: 10, score: 1.0 }])
    end.to raise_error(ArgumentError, "Jury rubric observations need criterion_points")

    expect do
      described_class.new(observations: [
                            { team: 1, criterion: "demo", juror: 10, score: 1.0, criterion_points: 5.0 },
                            { team: 2, criterion: "demo", juror: 10, score: 1.0, criterion_points: 4.0 }
                          ])
    end.to raise_error(ArgumentError, "Jury rubric criterion scales must be consistent")
  end

  it "reports initial-fit and bootstrap progress" do
    progress = []

    described_class.new(observations:, settings: { bootstrap: 3 }, progress: ->(value) { progress << value }).calculate

    expect(progress.first(2)).to eq([0.0, 0.1])
    expect(progress.last).to eq(1.0)
    expect(progress.length).to eq(5)
  end
end
