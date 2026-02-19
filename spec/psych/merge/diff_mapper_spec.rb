# frozen_string_literal: true

require "psych/merge"

RSpec.describe Psych::Merge::DiffMapper do
  let(:mapper) { described_class.new }

  describe "#map" do
    context "with a simple key value change" do
      let(:diff_text) do
        <<~DIFF
          --- a/config.yml
          +++ b/config.yml
          @@ -1,3 +1,3 @@
           name: my-project
          -version: 1.0.0
          +version: 2.0.0
           author: test
        DIFF
      end

      let(:original_content) do
        <<~YAML
          name: my-project
          version: 1.0.0
          author: test
        YAML
      end

      it "maps the change to the correct key path" do
        mappings = mapper.map(diff_text, original_content)

        expect(mappings.length).to eq(1)
        expect(mappings.first.path).to eq(["version"])
        expect(mappings.first.operation).to eq(:modify)
      end
    end

    context "with nested key changes" do
      let(:diff_text) do
        <<~DIFF
          --- a/rubocop.yml
          +++ b/rubocop.yml
          @@ -1,5 +1,6 @@
           AllCops:
             Exclude:
               - tmp/**/*
          +    - examples/**/*
             TargetRubyVersion: 3.2
        DIFF
      end

      let(:original_content) do
        <<~YAML
          AllCops:
            Exclude:
              - tmp/**/*
            TargetRubyVersion: 3.2
        YAML
      end

      it "maps the change to the nested key path" do
        mappings = mapper.map(diff_text, original_content)

        expect(mappings.length).to eq(1)
        expect(mappings.first.path).to include("AllCops")
        expect(mappings.first.operation).to eq(:add)
      end
    end

    context "with multiple changes to different keys" do
      let(:diff_text) do
        <<~DIFF
          --- a/config.yml
          +++ b/config.yml
          @@ -1,4 +1,5 @@
           database:
             host: localhost
          +  port: 5432
           cache:
          -  enabled: false
          +  enabled: true
        DIFF
      end

      let(:original_content) do
        <<~YAML
          database:
            host: localhost
          cache:
            enabled: false
        YAML
      end

      it "maps changes to separate paths" do
        mappings = mapper.map(diff_text, original_content)

        paths = mappings.map(&:path)
        expect(paths.flatten).to include("database")
        expect(paths.flatten).to include("cache")
      end
    end

    context "with addition of a new top-level key" do
      let(:diff_text) do
        <<~DIFF
          --- a/config.yml
          +++ b/config.yml
          @@ -1,2 +1,4 @@
           existing: value
          +new_key: new_value
          +another: thing
        DIFF
      end

      let(:original_content) do
        <<~YAML
          existing: value
        YAML
      end

      it "identifies additions" do
        mappings = mapper.map(diff_text, original_content)

        additions = mappings.select { |m| m.operation == :add }
        expect(additions).not_to be_empty
      end
    end

    context "with removal of a key" do
      let(:diff_text) do
        <<~DIFF
          --- a/config.yml
          +++ b/config.yml
          @@ -1,3 +1,2 @@
           keep: this
          -remove: this
           also_keep: that
        DIFF
      end

      let(:original_content) do
        <<~YAML
          keep: this
          remove: this
          also_keep: that
        YAML
      end

      it "identifies removals" do
        mappings = mapper.map(diff_text, original_content)

        removals = mappings.select { |m| m.operation == :remove }
        expect(removals).not_to be_empty
        expect(removals.first.path).to eq(["remove"])
      end
    end
  end

  describe "#create_analysis" do
    it "returns a FileAnalysis for valid YAML" do
      content = "key: value"
      analysis = mapper.create_analysis(content)

      expect(analysis).to be_a(Psych::Merge::FileAnalysis)
      expect(analysis.valid?).to be(true)
    end
  end

  describe "edge cases" do
    context "with empty diff" do
      let(:diff_text) { "" }
      let(:original_content) { "key: value" }

      it "returns empty mappings" do
        mappings = mapper.map(diff_text, original_content)
        expect(mappings).to be_empty
      end
    end

    context "with deeply nested structure" do
      let(:diff_text) do
        <<~DIFF
          --- a/config.yml
          +++ b/config.yml
          @@ -1,6 +1,7 @@
           level1:
             level2:
               level3:
                 deep_key: old_value
          +      new_deep_key: new_value
        DIFF
      end

      let(:original_content) do
        <<~YAML
          level1:
            level2:
              level3:
                deep_key: old_value
        YAML
      end

      it "maps to nested path" do
        mappings = mapper.map(diff_text, original_content)

        expect(mappings.first.path).to include("level1")
      end
    end
  end
end
