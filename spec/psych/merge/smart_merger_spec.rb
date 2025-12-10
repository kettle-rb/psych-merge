# frozen_string_literal: true

RSpec.describe Psych::Merge::SmartMerger do
  describe "#initialize" do
    it "creates a merger with valid YAML" do
      template = "key: template_value"
      dest = "key: dest_value"

      merger = described_class.new(template, dest)

      expect(merger.valid?).to be(true)
      expect(merger.template_analysis).to be_a(Psych::Merge::FileAnalysis)
      expect(merger.dest_analysis).to be_a(Psych::Merge::FileAnalysis)
    end

    it "raises TemplateParseError for invalid template" do
      template = "key: value\n  bad: indent"
      dest = "key: value"

      expect {
        described_class.new(template, dest)
      }.to raise_error(Psych::Merge::TemplateParseError)
    end

    it "raises DestinationParseError for invalid destination" do
      template = "key: value"
      dest = "key: value\n  bad: indent"

      expect {
        described_class.new(template, dest)
      }.to raise_error(Psych::Merge::DestinationParseError)
    end

    it "accepts configuration options" do
      template = "key: value"
      dest = "key: value"

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: "custom-token",
      )

      expect(merger.preference).to eq(:template)
      expect(merger.add_template_only_nodes).to be(true)
      expect(merger.freeze_token).to eq("custom-token")
    end
  end

  describe "#merge" do
    context "with destination preference (default)" do
      it "keeps destination value when keys match" do
        template = "key: template_value"
        dest = "key: dest_value"

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).to include("dest_value")
        expect(result).not_to include("template_value")
      end

      it "keeps destination-only keys" do
        template = "common: value"
        dest = <<~YAML
          common: value
          dest_only: special
        YAML

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).to include("dest_only")
        expect(result).to include("special")
      end

      it "does not add template-only keys by default" do
        template = <<~YAML
          common: value
          template_only: new
        YAML
        dest = "common: value"

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).not_to include("template_only")
      end
    end

    context "with template preference" do
      it "keeps template value when keys match" do
        template = "key: template_value"
        dest = "key: dest_value"

        merger = described_class.new(
          template,
          dest,
          preference: :template,
        )
        result = merger.merge

        expect(result).to include("template_value")
        expect(result).not_to include("dest_value")
      end
    end

    context "with add_template_only_nodes enabled" do
      it "adds template-only keys" do
        template = <<~YAML
          common: value
          template_only: new_feature
        YAML
        dest = "common: value"

        merger = described_class.new(
          template,
          dest,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to include("template_only")
        expect(result).to include("new_feature")
      end
    end

    context "with freeze blocks" do
      it "preserves destination freeze blocks" do
        template = <<~YAML
          normal: template_value
          frozen: template_frozen
        YAML
        dest = <<~YAML
          normal: dest_value
          # psych-merge:freeze
          frozen: dest_secret_value
          # psych-merge:unfreeze
        YAML

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).to include("dest_secret_value")
        expect(result).to include("psych-merge:freeze")
        expect(result).to include("psych-merge:unfreeze")
      end
    end

    context "with comments" do
      it "preserves comments from destination" do
        template = "key: value"
        dest = <<~YAML
          # Important comment
          key: value
        YAML

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).to include("Important comment")
      end
    end

    context "with anchors and aliases" do
      it "preserves anchor definitions" do
        template = <<~YAML
          defaults: &defaults
            adapter: postgres
        YAML
        dest = <<~YAML
          defaults: &defaults
            adapter: mysql
        YAML

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).to include("&defaults")
        expect(result).to include("mysql")
      end
    end
  end

  describe "#merge_with_debug" do
    it "returns detailed merge information" do
      template = "key: template_value"
      dest = "key: dest_value"

      merger = described_class.new(template, dest)
      debug_result = merger.merge_with_debug

      expect(debug_result).to have_key(:content)
      expect(debug_result).to have_key(:statistics)
      expect(debug_result).to have_key(:decisions)
      expect(debug_result).to have_key(:template_analysis)
      expect(debug_result).to have_key(:dest_analysis)
    end

    it "includes statistics about the merge" do
      template = <<~YAML
        key1: value1
        key2: value2
      YAML
      dest = <<~YAML
        key1: dest_value1
        key3: value3
      YAML

      merger = described_class.new(template, dest)
      debug_result = merger.merge_with_debug

      expect(debug_result[:statistics][:total_decisions]).to be > 0
    end
  end

  describe "#valid?" do
    it "returns true when both files are valid" do
      merger = described_class.new("key: value", "key: value")
      expect(merger.valid?).to be(true)
    end
  end

  describe "complex scenarios" do
    it "handles nested structures" do
      template = <<~YAML
        database:
          host: localhost
          port: 5432
        cache:
          enabled: true
      YAML
      dest = <<~YAML
        database:
          host: production.example.com
          port: 5432
        cache:
          enabled: false
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("production.example.com")
      expect(result).to include("enabled: false")
    end

    it "handles sequences" do
      template = <<~YAML
        items:
          - one
          - two
      YAML
      dest = <<~YAML
        items:
          - alpha
          - beta
          - gamma
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("alpha")
      expect(result).to include("gamma")
    end

    it "handles empty files" do
      template = ""
      dest = "key: value"

      # Empty template should parse but have no nodes
      expect {
        described_class.new(template, dest)
      }.not_to raise_error
    end

    it "handles mixed content" do
      template = <<~YAML
        # Header comment
        version: "1.0"

        settings:
          debug: false
          log_level: info

        # Footer
      YAML
      dest = <<~YAML
        # Custom header
        version: "2.0"

        settings:
          debug: true
          log_level: debug
          custom_setting: enabled

        # Custom footer
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      # Should keep destination values
      expect(result).to include('version: "2.0"')
      expect(result).to include("debug: true")
      expect(result).to include("custom_setting")
    end
  end

  describe "#errors" do
    it "returns empty array for valid files" do
      merger = described_class.new("key: value", "key: value")
      expect(merger.errors).to be_empty
    end
  end

  describe "edge cases" do
    it "handles YAML with special characters in values" do
      template = <<~YAML
        url: "https://example.com?param=value&other=test"
        regex: "^[a-z]+$"
      YAML
      dest = <<~YAML
        url: "https://custom.com?param=custom"
        regex: "^[A-Z]+$"
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("custom.com")
    end

    it "handles multiline strings" do
      template = <<~YAML
        description: |
          This is a
          multiline string
      YAML
      dest = <<~YAML
        description: |
          Custom description
          with multiple lines
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("Custom description")
    end

    it "handles YAML with null values" do
      template = <<~YAML
        present: value
        absent: ~
      YAML
      dest = <<~YAML
        present: custom
        absent: ~
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("custom")
    end

    it "handles YAML with boolean values" do
      template = <<~YAML
        enabled: true
        disabled: false
      YAML
      dest = <<~YAML
        enabled: false
        disabled: true
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("enabled: false")
      expect(result).to include("disabled: true")
    end

    it "handles YAML with numeric values" do
      template = <<~YAML
        count: 100
        ratio: 0.5
      YAML
      dest = <<~YAML
        count: 200
        ratio: 0.75
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("count: 200")
      expect(result).to include("ratio: 0.75")
    end

    it "handles deeply nested freeze blocks" do
      template = <<~YAML
        level1:
          level2:
            value: template
      YAML
      dest = <<~YAML
        level1:
          # psych-merge:freeze
          level2:
            value: frozen
          # psych-merge:unfreeze
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("psych-merge:freeze")
    end
  end

  describe "custom signature generator" do
    it "uses custom signature generator" do
      custom_generator = ->(node) {
        if node.respond_to?(:key_name) && node.key_name == "special"
          [:special, "custom_sig"]
        else
          node  # Fall through to default
        end
      }

      template = <<~YAML
        normal: template_value
        special: template_special
      YAML
      dest = <<~YAML
        normal: dest_value
        special: dest_special
      YAML

      merger = described_class.new(
        template,
        dest,
        signature_generator: custom_generator,
      )
      result = merger.merge

      expect(result).to include("dest_value")
    end
  end

  describe "regression tests" do
    # Regression test for bug where destination-only keys with nested mappings
    # would cause the key to be emitted twice due to overlapping line ranges.
    # The bug was in NodeWrapper where end_line was calculated as node.end_line + 1,
    # but Psych's end_line is already exclusive, so this caused off-by-one errors.
    it "does not duplicate keys when destination adds a new nested mapping" do
      template = <<~YAML
        name: my-project
        version: 1.0.0
        database:
          host: localhost
          port: 5432
      YAML

      dest = <<~YAML
        name: my-project
        version: 1.0.0
        database:
          host: localhost
          port: 5432
        cache:
          enabled: true
          ttl: 3600
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      # The key "cache" should appear exactly once
      expect(result.scan(/^cache:/).length).to eq(1), 
        "Expected 'cache:' to appear once but got: #{result.inspect}"
      
      # Verify the full structure is correct
      expect(result).to include("cache:")
      expect(result).to include("enabled: true")
      expect(result).to include("ttl: 3600")
    end

    it "merge is idempotent when destination adds nested mappings" do
      template = <<~YAML
        name: my-project
        database:
          host: localhost
      YAML

      dest = <<~YAML
        name: my-project
        database:
          host: localhost
        cache:
          enabled: true
      YAML

      merger1 = described_class.new(template, dest)
      result1 = merger1.merge

      # Merge again using the result as both template and destination
      merger2 = described_class.new(result1, result1)
      result2 = merger2.merge

      expect(result2).to eq(result1), 
        "Merge should be idempotent.\nFirst: #{result1.inspect}\nSecond: #{result2.inspect}"
    end
  end
end
