# frozen_string_literal: true

require "psych/merge"
require "ast/merge/rspec/shared_examples"

RSpec.describe "Psych reproducible merge" do
  let(:fixtures_path) { File.expand_path("../fixtures/reproducible", __dir__) }
  let(:merger_class) { Psych::Merge::SmartMerger }
  let(:file_extension) { "yml" }

  describe "basic merge scenarios (destination wins by default)" do
    context "when a key is removed in destination" do
      it_behaves_like "a reproducible merge", "01_key_removed"
    end

    context "when a key is added in destination" do
      it_behaves_like "a reproducible merge", "02_key_added"
    end

    context "when a value is changed in destination" do
      it_behaves_like "a reproducible merge", "03_value_changed"
    end
  end
end
