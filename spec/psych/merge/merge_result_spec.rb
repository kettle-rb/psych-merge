# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe Psych::Merge::MergeResult do
  # Use shared examples to validate base MergeResultBase integration
  it_behaves_like "Ast::Merge::MergeResultBase" do
    let(:merge_result_class) { described_class }
    let(:build_merge_result) { -> { described_class.new } }
  end

  describe "#initialize" do
    it "starts with empty lines" do
      result = described_class.new
      expect(result.empty?).to be(true)
      expect(result.line_count).to eq(0)
    end

    it "initializes statistics" do
      result = described_class.new
      expect(result.statistics[:total_decisions]).to eq(0)
    end
  end

  describe "#add_line" do
    it "adds a line to the result" do
      result = described_class.new
      result.add_line("key: value", decision: :kept_template, source: :template)

      expect(result.line_count).to eq(1)
      expect(result.lines.first[:content]).to eq("key: value")
    end

    it "tracks the decision" do
      result = described_class.new
      result.add_line("key: value", decision: :kept_template, source: :template)

      expect(result.decisions.length).to eq(1)
      expect(result.decisions.first[:decision]).to eq(:kept_template)
    end

    it "updates statistics" do
      result = described_class.new
      result.add_line("key: value", decision: :kept_template, source: :template)

      expect(result.statistics[:template_lines]).to eq(1)
      expect(result.statistics[:total_decisions]).to eq(1)
    end
  end

  describe "#add_lines" do
    it "adds multiple lines" do
      result = described_class.new
      result.add_lines(["line1", "line2", "line3"], decision: :kept_dest, source: :destination)

      expect(result.line_count).to eq(3)
    end

    it "tracks original line numbers" do
      result = described_class.new
      result.add_lines(["line1", "line2"], decision: :kept_dest, source: :destination, start_line: 5)

      expect(result.lines[0][:original_line]).to eq(5)
      expect(result.lines[1][:original_line]).to eq(6)
    end
  end

  describe "#add_blank_line" do
    it "adds an empty line" do
      result = described_class.new
      result.add_blank_line

      expect(result.line_count).to eq(1)
      expect(result.lines.first[:content]).to eq("")
    end
  end

  describe "#add_freeze_block" do
    it "adds all lines from a freeze block" do
      lines = ["# freeze", "key: value", "# unfreeze"]
      freeze_node = Psych::Merge::FreezeNode.new(
        start_line: 1,
        end_line: 3,
        lines: lines,
      )

      result = described_class.new
      result.add_freeze_block(freeze_node)

      expect(result.line_count).to eq(3)
      expect(result.lines.all? { |l| l[:decision] == :freeze_block }).to be(true)
    end
  end

  describe "#to_yaml" do
    it "joins lines with newlines" do
      result = described_class.new
      result.add_line("key: value", decision: :kept_template, source: :template)
      result.add_line("other: stuff", decision: :kept_template, source: :template)

      yaml = result.to_yaml
      expect(yaml).to eq("key: value\nother: stuff\n")
    end

    it "adds trailing newline" do
      result = described_class.new
      result.add_line("key: value", decision: :kept_template, source: :template)

      expect(result.to_yaml).to end_with("\n")
    end

    it "returns empty string with newline for empty result" do
      result = described_class.new
      # Empty results should not have a newline
      expect(result.to_yaml).to eq("")
    end
  end

  describe "#content" do
    it "is an alias for to_yaml" do
      result = described_class.new
      result.add_line("key: value", decision: :kept_template, source: :template)

      expect(result.content).to eq(result.to_yaml)
    end
  end

  describe "#decision_summary" do
    it "summarizes decisions by type" do
      result = described_class.new
      result.add_line("line1", decision: :kept_template, source: :template)
      result.add_line("line2", decision: :kept_template, source: :template)
      result.add_line("line3", decision: :kept_destination, source: :destination)

      summary = result.decision_summary
      expect(summary[:kept_template]).to eq(2)
      expect(summary[:kept_destination]).to eq(1)
    end
  end

  describe "#inspect" do
    it "returns a readable string" do
      result = described_class.new
      result.add_line("key: value", decision: :kept_template, source: :template)

      expect(result.inspect).to include("MergeResult")
      expect(result.inspect).to include("lines=1")
    end
  end

  describe "#add_mapping_entry" do
    let(:yaml) do
      <<~YAML
        key: value
        other: stuff
      YAML
    end

    let(:analysis) { Psych::Merge::FileAnalysis.new(yaml) }

    it "adds lines from mapping entry" do
      result = described_class.new
      entry = analysis.statements.first

      result.add_mapping_entry(entry, decision: :kept_dest, source: :destination)

      expect(result.line_count).to be >= 1
      expect(result.to_yaml).to include("key: value")
    end

    it "handles entry without line info gracefully" do
      result = described_class.new

      # Create a mock entry without start_line
      entry = instance_double(Psych::Merge::MappingEntry, start_line: nil, end_line: nil)

      # Should not raise error
      expect { result.add_mapping_entry(entry, decision: :kept_dest, source: :destination) }.not_to raise_error
      expect(result.empty?).to be(true)
    end
  end

  describe "#add_lines_from" do
    it "adds lines with starting line number" do
      result = described_class.new
      result.add_lines_from(["line1", "line2"], decision: :merged, source: :merged, start_line: 10)

      expect(result.lines[0][:original_line]).to eq(10)
      expect(result.lines[1][:original_line]).to eq(11)
    end

    it "adds lines without starting line number" do
      result = described_class.new
      result.add_lines_from(["line1", "line2"], decision: :merged, source: :merged)

      expect(result.lines[0][:original_line]).to be_nil
      expect(result.lines[1][:original_line]).to be_nil
    end
  end

  describe "statistics tracking" do
    it "tracks freeze_preserved_lines" do
      lines = ["# freeze", "key: value", "# unfreeze"]
      freeze_node = Psych::Merge::FreezeNode.new(
        start_line: 1,
        end_line: 3,
        lines: lines,
      )

      result = described_class.new
      result.add_freeze_block(freeze_node)

      expect(result.statistics[:freeze_preserved_lines]).to eq(3)
    end

    it "tracks merged_lines for other decisions" do
      result = described_class.new
      result.add_line("line", decision: :merged, source: :merged)
      result.add_line("added", decision: :added, source: :template)

      expect(result.statistics[:merged_lines]).to eq(2)
    end

    it "tracks dest_lines correctly" do
      result = described_class.new
      result.add_line("dest line", decision: :kept_destination, source: :destination)

      expect(result.statistics[:dest_lines]).to eq(1)
    end
  end

  describe "decision tracking" do
    it "records timestamp for each decision" do
      result = described_class.new
      result.add_line("line", decision: :kept_template, source: :template)

      expect(result.decisions.first[:timestamp]).to be_a(Time)
    end

    it "records line number for decisions" do
      result = described_class.new
      result.add_line("line", decision: :kept_template, source: :template, original_line: 5)

      expect(result.decisions.first[:line]).to eq(5)
    end
  end
end
