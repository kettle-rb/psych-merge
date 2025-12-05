# frozen_string_literal: true

# External gems
require "psych"
require "version_gem"

# This gem
require_relative "merge/version"

module Psych
  module Merge
    class Error < StandardError; end
    # Your code goes here...
  end
end

Psych::Merge::Version.class_eval do
  extend VersionGem::Basic
end
