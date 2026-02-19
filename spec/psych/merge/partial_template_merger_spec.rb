# frozen_string_literal: true

require "psych/merge"

RSpec.describe Psych::Merge::PartialTemplateMerger do
  describe "#merge" do
    context "with sequence at key path" do
      let(:template) do
        <<~YAML
          - examples/**/*
          - vendor/**/*
        YAML
      end

      let(:destination) do
        <<~YAML
          AllCops:
            Exclude:
              - tmp/**/*
              - coverage/**/*
            TargetRubyVersion: 3.2
        YAML
      end

      it "merges template items into existing sequence" do
        merger = described_class.new(
          template: template,
          destination: destination,
          key_path: ["AllCops", "Exclude"],
          add_missing: true,
        )
        result = merger.merge

        expect(result.key_path_found?).to be(true)
        expect(result.changed).to be(true)
        expect(result.content).to include("tmp/**/*")
        expect(result.content).to include("examples/**/*")
        expect(result.content).to include("vendor/**/*")
      end

      it "keeps destination items when add_missing is true" do
        merger = described_class.new(
          template: template,
          destination: destination,
          key_path: ["AllCops", "Exclude"],
          add_missing: true,
          remove_missing: false,
        )
        result = merger.merge

        expect(result.content).to include("tmp/**/*")
        expect(result.content).to include("coverage/**/*")
      end
    end

    context "with mapping at key path" do
      let(:template) do
        <<~YAML
          NewCops: enable
          SuggestExtensions: false
        YAML
      end

      let(:destination) do
        <<~YAML
          AllCops:
            TargetRubyVersion: 3.2
            Exclude:
              - tmp/**/*
        YAML
      end

      it "merges template keys into existing mapping" do
        merger = described_class.new(
          template: template,
          destination: destination,
          key_path: ["AllCops"],
          add_missing: true,
        )
        result = merger.merge

        expect(result.key_path_found?).to be(true)
        expect(result.content).to include("NewCops")
        expect(result.content).to include("TargetRubyVersion")
      end
    end

    context "when key path not found" do
      let(:template) { "value" }
      let(:destination) do
        <<~YAML
          ExistingKey: existing_value
        YAML
      end

      it "skips by default" do
        merger = described_class.new(
          template: template,
          destination: destination,
          key_path: ["NonExistent", "Path"],
        )
        result = merger.merge

        expect(result.key_path_found?).to be(false)
        expect(result.changed).to be(false)
        expect(result.content).to eq(destination)
      end

      it "adds when when_missing: :add" do
        merger = described_class.new(
          template: template,
          destination: destination,
          key_path: ["NewKey"],
          when_missing: :add,
        )
        result = merger.merge

        expect(result.key_path_found?).to be(false)
        expect(result.changed).to be(true)
        expect(result.content).to include("NewKey")
      end
    end

    context "with remove_missing: true" do
      let(:template) do
        <<~YAML
          - keep_this/**/*
        YAML
      end

      let(:destination) do
        <<~YAML
          AllCops:
            Exclude:
              - keep_this/**/*
              - remove_this/**/*
        YAML
      end

      it "removes items not in template" do
        merger = described_class.new(
          template: template,
          destination: destination,
          key_path: ["AllCops", "Exclude"],
          remove_missing: true,
          add_missing: false,
        )
        result = merger.merge

        expect(result.content).to include("keep_this/**/*")
        expect(result.content).not_to include("remove_this/**/*")
      end
    end

    context "with deeply nested key path" do
      let(:template) { "new_value" }
      let(:destination) do
        <<~YAML
          level1:
            level2:
              level3:
                target: old_value
        YAML
      end

      it "navigates to deep key path" do
        merger = described_class.new(
          template: template,
          destination: destination,
          key_path: ["level1", "level2", "level3", "target"],
          preference: :template,
        )
        result = merger.merge

        expect(result.key_path_found?).to be(true)
      end
    end
  end

  describe "#initialize" do
    it "raises ArgumentError for empty key_path" do
      expect {
        described_class.new(
          template: "value",
          destination: "key: value",
          key_path: [],
        )
      }.to raise_error(ArgumentError, /key_path cannot be empty/)
    end

    it "accepts string key_path and converts to array" do
      merger = described_class.new(
        template: "value",
        destination: "key: value",
        key_path: "key",
      )
      expect(merger.key_path).to eq(["key"])
    end
  end
end
