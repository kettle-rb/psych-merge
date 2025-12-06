# frozen_string_literal: true

RSpec.describe Psych::Merge::MappingMatchRefiner do
  subject(:refiner) { described_class.new(**options) }

  let(:options) { {} }

  describe "#initialize" do
    it "uses default threshold of 0.5" do
      expect(refiner.threshold).to eq(0.5)
    end

    it "uses default key_weight of 0.7" do
      expect(refiner.key_weight).to eq(0.7)
    end

    it "uses default value_weight of 0.3" do
      expect(refiner.value_weight).to eq(0.3)
    end

    context "with custom options" do
      let(:options) { {threshold: 0.6, key_weight: 0.8, value_weight: 0.2} }

      it "uses custom threshold" do
        expect(refiner.threshold).to eq(0.6)
      end

      it "uses custom key_weight" do
        expect(refiner.key_weight).to eq(0.8)
      end

      it "uses custom value_weight" do
        expect(refiner.value_weight).to eq(0.2)
      end
    end
  end

  describe "#call" do
    let(:template_yaml) { <<~YAML }
      database_url: postgres://localhost/myapp
      cache_timeout: 3600
      api_endpoint: https://api.example.com
    YAML

    let(:dest_yaml) { <<~YAML }
      database_uri: postgres://localhost/production
      cache_ttl: 7200
      error_handler: default
    YAML

    let(:template_analysis) { Psych::Merge::FileAnalysis.new(template_yaml) }
    let(:dest_analysis) { Psych::Merge::FileAnalysis.new(dest_yaml) }

    let(:template_entries) do
      template_analysis.statements.select { |n| n.respond_to?(:key) && n.key }
    end

    let(:dest_entries) do
      dest_analysis.statements.select { |n| n.respond_to?(:key) && n.key }
    end

    it "matches keys with similar names" do
      matches = refiner.call(template_entries, dest_entries)

      # database_url should match database_uri (similar key)
      db_match = matches.find { |m| m.template_node.key.to_s.include?("database") }
      expect(db_match).not_to be_nil
      expect(db_match.dest_node.key.to_s).to eq("database_uri")
    end

    it "matches keys with similar semantics" do
      matches = refiner.call(template_entries, dest_entries)

      # cache_timeout should match cache_ttl (similar concept)
      cache_match = matches.find { |m| m.template_node.key.to_s.include?("cache") }
      expect(cache_match).not_to be_nil
      expect(cache_match.dest_node.key.to_s).to include("cache")
    end

    it "returns MatchResult objects with scores" do
      matches = refiner.call(template_entries, dest_entries)

      expect(matches).to all(be_a(Ast::Merge::MatchRefinerBase::MatchResult))
      expect(matches.map(&:score)).to all(be_a(Float))
      expect(matches.map(&:score)).to all(be >= refiner.threshold)
    end

    context "with high threshold" do
      let(:options) { {threshold: 0.9} }

      it "returns fewer matches" do
        matches = refiner.call(template_entries, dest_entries)

        # With 0.9 threshold, only very similar keys should match
        expect(matches.size).to be <= 1
      end
    end

    context "when one list is empty" do
      it "returns empty array for empty template" do
        matches = refiner.call([], dest_entries)
        expect(matches).to eq([])
      end

      it "returns empty array for empty destination" do
        matches = refiner.call(template_entries, [])
        expect(matches).to eq([])
      end
    end

    context "with exact key matches but different values" do
      let(:dest_yaml) { <<~YAML }
        database_url: postgres://localhost/production
      YAML

      it "matches keys with identical names" do
        matches = refiner.call(template_entries, dest_entries)

        db_match = matches.find { |m| m.template_node.key.to_s == "database_url" }
        expect(db_match).not_to be_nil
        expect(db_match.dest_node.key.to_s).to eq("database_url")
        expect(db_match.score).to be >= 0.7
      end
    end

    context "with naming convention differences" do
      let(:template_yaml) { <<~YAML }
        database-url: postgres://localhost/myapp
        api-key: secret123
      YAML

      let(:dest_yaml) { <<~YAML }
        database_url: postgres://localhost/production
        apiKey: secret456
      YAML

      it "normalizes keys for comparison" do
        matches = refiner.call(template_entries, dest_entries)

        # database-url should match database_url (underscore vs hyphen)
        db_match = matches.find { |m| m.template_node.key.to_s.include?("database") }
        expect(db_match).not_to be_nil

        # api-key should match apiKey (snake_case vs camelCase)
        api_match = matches.find { |m| m.template_node.key.to_s.include?("api") }
        expect(api_match).not_to be_nil
      end
    end
  end

  describe "greedy matching" do
    let(:template_yaml) { <<~YAML }
      foo: 1
      bar: 2
      baz: 3
    YAML

    let(:dest_yaml) { <<~YAML }
      fooo: 1
      barr: 2
    YAML

    let(:template_analysis) { Psych::Merge::FileAnalysis.new(template_yaml) }
    let(:dest_analysis) { Psych::Merge::FileAnalysis.new(dest_yaml) }

    let(:template_entries) do
      template_analysis.statements.select { |n| n.respond_to?(:key) && n.key }
    end

    let(:dest_entries) do
      dest_analysis.statements.select { |n| n.respond_to?(:key) && n.key }
    end

    it "ensures each destination node is matched at most once" do
      matches = refiner.call(template_entries, dest_entries)

      dest_nodes = matches.map(&:dest_node)
      expect(dest_nodes.uniq.size).to eq(dest_nodes.size)
    end

    it "ensures each template node is matched at most once" do
      matches = refiner.call(template_entries, dest_entries)

      template_nodes = matches.map(&:template_node)
      expect(template_nodes.uniq.size).to eq(template_nodes.size)
    end
  end
end
