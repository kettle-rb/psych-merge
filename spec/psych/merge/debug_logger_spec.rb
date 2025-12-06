# frozen_string_literal: true

RSpec.describe Psych::Merge::DebugLogger do
  around do |example|
    original = ENV["PSYCH_MERGE_DEBUG"]
    example.run
    ENV["PSYCH_MERGE_DEBUG"] = original
  end

  describe ".enabled?" do
    it "returns false by default" do
      ENV.delete("PSYCH_MERGE_DEBUG")
      expect(described_class.enabled?).to be(false)
    end

    it "returns true when env is '1'" do
      ENV["PSYCH_MERGE_DEBUG"] = "1"
      expect(described_class.enabled?).to be(true)
    end

    it "returns true when env is 'true'" do
      ENV["PSYCH_MERGE_DEBUG"] = "true"
      expect(described_class.enabled?).to be(true)
    end
  end

  describe ".debug" do
    it "does not output when disabled" do
      ENV.delete("PSYCH_MERGE_DEBUG")

      expect {
        described_class.debug("test message")
      }.not_to output.to_stderr
    end

    it "outputs when enabled" do
      ENV["PSYCH_MERGE_DEBUG"] = "1"

      expect {
        described_class.debug("test message")
      }.to output(/test message/).to_stderr
    end

    it "includes context in output" do
      ENV["PSYCH_MERGE_DEBUG"] = "1"

      expect {
        described_class.debug("test", {key: "value"})
      }.to output(/key.*value/).to_stderr
    end
  end

  describe ".info" do
    it "does not output when disabled" do
      ENV.delete("PSYCH_MERGE_DEBUG")

      expect {
        described_class.info("info message")
      }.not_to output.to_stderr
    end

    it "outputs with INFO prefix when enabled" do
      ENV["PSYCH_MERGE_DEBUG"] = "1"

      expect {
        described_class.info("info message")
      }.to output(/INFO.*info message/).to_stderr
    end
  end

  describe ".warning" do
    it "always outputs warnings" do
      ENV.delete("PSYCH_MERGE_DEBUG")

      expect {
        described_class.warning("warning message")
      }.to output(/WARNING.*warning message/).to_stderr
    end
  end

  describe ".time" do
    it "times block execution and logs when enabled" do
      ENV["PSYCH_MERGE_DEBUG"] = "1"

      expect {
        result = described_class.time("test_operation") do
          sleep(0.01)
          "block_result"
        end
        expect(result).to eq("block_result")
      }.to output(/Starting.*test_operation.*Completed.*test_operation.*real_ms/m).to_stderr
    end

    it "returns block result without logging when disabled" do
      ENV.delete("PSYCH_MERGE_DEBUG")

      expect {
        result = described_class.time("operation") do
          "result_value"
        end
        expect(result).to eq("result_value")
      }.not_to output.to_stderr
    end

    it "includes real, user, and system time in output" do
      ENV["PSYCH_MERGE_DEBUG"] = "1"

      expect {
        described_class.time("timed_op") { 1 + 1 }
      }.to output(/real_ms.*user_ms.*system_ms/).to_stderr
    end

    it "warns and returns block result when benchmark is unavailable" do
      ENV["PSYCH_MERGE_DEBUG"] = "1"
      stub_const("Psych::Merge::DebugLogger::BENCHMARK_AVAILABLE", false)

      expect {
        result = described_class.time("test_operation") do
          "block_result"
        end
        expect(result).to eq("block_result")
      }.to output(/WARNING.*Benchmark gem not available.*test_operation/).to_stderr
    end
  end

  describe ".log_node" do
    around do |example|
      ENV["PSYCH_MERGE_DEBUG"] = "1"
      example.run
    end

    it "logs FreezeNode information" do
      lines = ["# freeze", "key: value", "# unfreeze"]
      freeze_node = Psych::Merge::FreezeNode.new(
        start_line: 1,
        end_line: 3,
        lines: lines
      )

      expect {
        described_class.log_node(freeze_node, label: "Test")
      }.to output(/FreezeNode/).to_stderr
    end

    it "logs MappingEntry information" do
      yaml = "key: value"
      analysis = Psych::Merge::FileAnalysis.new(yaml)
      entry = analysis.nodes.first

      expect {
        described_class.log_node(entry, label: "Entry")
      }.to output(/MappingEntry/).to_stderr
    end

    it "logs NodeWrapper information" do
      yaml = "key: value"
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = Psych::Merge::NodeWrapper.new(root, lines: yaml.lines.map(&:chomp))

      expect {
        described_class.log_node(wrapper, label: "Wrapper")
      }.to output(/Mapping/).to_stderr
    end

    it "logs unknown node types" do
      expect {
        described_class.log_node("string node", label: "Unknown")
      }.to output(/String/).to_stderr
    end

    it "does not log when disabled" do
      ENV.delete("PSYCH_MERGE_DEBUG")

      lines = ["# freeze", "key: value", "# unfreeze"]
      freeze_node = Psych::Merge::FreezeNode.new(
        start_line: 1,
        end_line: 3,
        lines: lines
      )

      expect {
        described_class.log_node(freeze_node)
      }.not_to output.to_stderr
    end
  end
end
