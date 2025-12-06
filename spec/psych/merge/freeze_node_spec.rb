# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe Psych::Merge::FreezeNode do
  # Use shared examples to validate base FreezeNodeBase integration
  it_behaves_like "Ast::Merge::FreezeNodeBase" do
    let(:freeze_node_class) { described_class }
    let(:default_pattern_type) { :hash_comment }
    let(:build_freeze_node) do
      ->(start_line:, end_line:, **opts) {
        # Build enough lines to cover the requested range
        lines = opts.delete(:lines) || begin
          result = []
          (1..end_line).each do |i|
            result << if i == start_line
              "# psych-merge:freeze"
            elsif i == end_line
              "# psych-merge:unfreeze"
            else
              "key_#{i}: value_#{i}"
            end
          end
          result
        end
        freeze_node_class.new(
          start_line: start_line,
          end_line: end_line,
          lines: lines,
          pattern_type: opts[:pattern_type] || :hash_comment,
          **opts.except(:pattern_type),
        )
      }
    end
  end

  # Psych-specific tests
  let(:lines) do
    [
      "# psych-merge:freeze",
      "frozen_key: frozen_value",
      "another: value",
      "# psych-merge:unfreeze",
    ]
  end

  describe "#initialize" do
    it "creates a freeze node with valid parameters" do
      node = described_class.new(
        start_line: 1,
        end_line: 4,
        lines: lines,
      )

      expect(node.start_line).to eq(1)
      expect(node.end_line).to eq(4)
      expect(node.lines.length).to eq(4)
    end

    it "extracts content correctly" do
      node = described_class.new(
        start_line: 1,
        end_line: 4,
        lines: lines,
      )

      expect(node.content).to include("frozen_key: frozen_value")
      expect(node.content).to include("psych-merge:freeze")
    end

    it "raises error when end_line is before start_line" do
      expect {
        described_class.new(start_line: 4, end_line: 1, lines: lines)
      }.to raise_error(Psych::Merge::FreezeNode::InvalidStructureError)
    end
  end

  describe "#location" do
    it "returns a location object" do
      node = described_class.new(start_line: 1, end_line: 4, lines: lines)
      location = node.location

      expect(location.start_line).to eq(1)
      expect(location.end_line).to eq(4)
    end

    it "location covers lines within range" do
      node = described_class.new(start_line: 1, end_line: 4, lines: lines)

      expect(node.location.cover?(1)).to be(true)
      expect(node.location.cover?(2)).to be(true)
      expect(node.location.cover?(4)).to be(true)
      expect(node.location.cover?(5)).to be(false)
    end
  end

  describe "#mapping?" do
    it "returns false" do
      node = described_class.new(start_line: 1, end_line: 4, lines: lines)
      expect(node.mapping?).to be(false)
    end
  end

  describe "#slice" do
    it "returns the content" do
      node = described_class.new(start_line: 1, end_line: 4, lines: lines)
      expect(node.slice).to eq(node.content)
    end
  end

  describe "#inspect" do
    it "returns a readable string" do
      node = described_class.new(start_line: 1, end_line: 4, lines: lines)
      expect(node.inspect).to include("FreezeNode")
      expect(node.inspect).to include("1..4")
    end
  end

  describe "#to_s" do
    it "returns same as inspect" do
      node = described_class.new(start_line: 1, end_line: 4, lines: lines)
      expect(node.to_s).to eq(node.inspect)
    end
  end

  describe "#sequence?" do
    it "returns false" do
      node = described_class.new(start_line: 1, end_line: 4, lines: lines)
      expect(node.sequence?).to be(false)
    end
  end

  describe "#scalar?" do
    it "returns false" do
      node = described_class.new(start_line: 1, end_line: 4, lines: lines)
      expect(node.scalar?).to be(false)
    end
  end

  describe "marker storage" do
    it "stores start marker" do
      node = described_class.new(
        start_line: 1,
        end_line: 4,
        lines: lines,
        start_marker: "# psych-merge:freeze",
      )

      expect(node.start_marker).to eq("# psych-merge:freeze")
    end

    it "stores end marker" do
      node = described_class.new(
        start_line: 1,
        end_line: 4,
        lines: lines,
        end_marker: "# psych-merge:unfreeze",
      )

      expect(node.end_marker).to eq("# psych-merge:unfreeze")
    end
  end

  describe "InvalidStructureError" do
    it "has start_line accessor" do
      described_class.new(start_line: 4, end_line: 1, lines: lines)
    rescue Psych::Merge::FreezeNode::InvalidStructureError => e
      expect(e.start_line).to eq(4)
      expect(e.end_line).to eq(1)
    end

    it "raises error when end_line is before start_line" do
      expect {
        described_class.new(start_line: 5, end_line: 2, lines: ["line1", "line2", "line3", "line4", "line5"])
      }.to raise_error(Psych::Merge::FreezeNode::InvalidStructureError, /before start line/)
    end

    it "raises error when lines array is empty" do
      expect {
        described_class.new(start_line: 1, end_line: 1, lines: [])
      }.to raise_error(Psych::Merge::FreezeNode::InvalidStructureError, /empty/)
    end
  end
end
