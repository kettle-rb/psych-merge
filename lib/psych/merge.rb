# frozen_string_literal: true

# External gems
require "psych"
require "version_gem"
require "set"

# This gem
require_relative "merge/version"

# Psych::Merge provides a generic YAML file smart merge system using Psych AST analysis.
# It intelligently merges template and destination YAML files by identifying matching
# keys and resolving differences using structural signatures.
#
# @example Basic usage
#   template = File.read("template.yml")
#   destination = File.read("destination.yml")
#   merger = Psych::Merge::SmartMerger.new(template, destination)
#   result = merger.merge
#
# @example With debug information
#   merger = Psych::Merge::SmartMerger.new(template, destination)
#   debug_result = merger.merge_with_debug
#   puts debug_result[:content]
#   puts debug_result[:statistics]
module Psych
  # Smart merge system for YAML files using Psych AST analysis.
  # Provides intelligent merging by understanding YAML structure
  # rather than treating files as plain text.
  #
  # @see SmartMerger Main entry point for merge operations
  # @see FileAnalysis Analyzes YAML structure
  # @see ConflictResolver Resolves content conflicts
  module Merge
    # Base error class for Psych::Merge
    class Error < StandardError; end

    # Raised when a YAML file has parsing errors
    class ParseError < Error
      # @return [String] The content that failed to parse
      attr_reader :content

      # @return [Array] The parse errors
      attr_reader :errors

      # @param message [String] Error message
      # @param content [String] The YAML source that failed to parse
      # @param errors [Array] Parse errors from Psych
      def initialize(message, content:, errors:)
        super(message)
        @content = content
        @errors = errors
      end
    end

    # Raised when the template file has syntax errors.
    #
    # @example Handling template parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue TemplateParseError => e
    #     puts "Template syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class TemplateParseError < ParseError; end

    # Raised when the destination file has syntax errors.
    #
    # @example Handling destination parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue DestinationParseError => e
    #     puts "Destination syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class DestinationParseError < ParseError; end

    autoload :CommentTracker, "psych/merge/comment_tracker"
    autoload :DebugLogger, "psych/merge/debug_logger"
    autoload :Emitter, "psych/merge/emitter"
    autoload :FreezeNode, "psych/merge/freeze_node"
    autoload :FileAnalysis, "psych/merge/file_analysis"
    autoload :MappingEntry, "psych/merge/file_analysis"
    autoload :MergeResult, "psych/merge/merge_result"
    autoload :NodeWrapper, "psych/merge/node_wrapper"
    autoload :ConflictResolver, "psych/merge/conflict_resolver"
    autoload :SmartMerger, "psych/merge/smart_merger"
  end
end

Psych::Merge::Version.class_eval do
  extend VersionGem::Basic
end
