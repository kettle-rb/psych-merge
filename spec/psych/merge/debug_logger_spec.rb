# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe Psych::Merge::DebugLogger do
  # Use the shared examples to validate base DebugLogger integration
  it_behaves_like "Ast::Merge::DebugLogger" do
    let(:described_logger) { described_class }
    let(:env_var_name) { "PSYCH_MERGE_DEBUG" }
    let(:log_prefix) { "[Psych::Merge]" }
  end

  describe "Psych-specific log_node override" do
    before do
      stub_env("PSYCH_MERGE_DEBUG" => "1")
    end

    it "logs FreezeNode information" do
      lines = ["# freeze", "key: value", "# unfreeze"]
      freeze_node = Psych::Merge::FreezeNode.new(
        start_line: 1,
        end_line: 3,
        lines: lines,
      )

      expect {
        described_class.log_node(freeze_node, label: "Test")
      }.to output(/FreezeNode/).to_stderr
    end

    it "logs MappingEntry information" do
      yaml = "key: value"
      analysis = Psych::Merge::FileAnalysis.new(yaml)
      entry = analysis.statements.first

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

    it "logs unknown node types using base extract_node_info" do
      expect {
        described_class.log_node("string node", label: "Unknown")
      }.to output(/String/).to_stderr
    end

    it "does not log when disabled" do
      stub_env("PSYCH_MERGE_DEBUG" => nil)

      lines = ["# freeze", "key: value", "# unfreeze"]
      freeze_node = Psych::Merge::FreezeNode.new(
        start_line: 1,
        end_line: 3,
        lines: lines,
      )

      expect {
        described_class.log_node(freeze_node)
      }.not_to output.to_stderr
    end
  end
end
