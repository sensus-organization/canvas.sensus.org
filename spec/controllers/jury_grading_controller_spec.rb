# frozen_string_literal: true

describe JuryGradingController do
  describe "#run_json" do
    it "returns an unwrapped run payload" do
      run = JuryGradingRun.new(workflow_state: "completed", algorithm_version: "test", settings: {}, results: {})

      json = controller.send(:run_json, run)

      expect(json).to include("workflow_state" => "completed", "algorithm_version" => "test")
      expect(json).not_to have_key("jury_grading_run")
    end

    it "includes calculation progress" do
      run = JuryGradingRun.new(workflow_state: "queued", algorithm_version: "test", settings: {}, results: {})
      progress = instance_double(Progress, model_name: Progress.model_name, as_json: { "progress" => { "id" => 9, "completion" => 10 } })
      allow(run).to receive(:progress).and_return(progress)

      expect(controller.send(:run_json, run).dig("progress", "completion")).to eq(10)
    end
  end

  describe "#calculate" do
    it "does not replace a published result" do
      assignment = instance_double(Assignment, grades_published?: true, published_jury_grading_run_id: nil)
      allow(assignment).to receive(:with_lock).and_yield
      allow(assignment).to receive(:reload)
      controller.instance_variable_set(:@assignment, assignment)

      expect(controller).to receive(:render).with(
        json: { message: "Jury results have already been published" },
        status: :unprocessable_content
      )

      controller.calculate
    end
  end
end
