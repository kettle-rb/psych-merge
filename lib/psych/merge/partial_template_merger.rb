# frozen_string_literal: true

module Psych
  module Merge
    # Merges a partial YAML template into a specific key path of a destination document.
    #
    # Unlike the full SmartMerger which merges entire documents, PartialTemplateMerger:
    # 1. Finds a specific key path in the destination (e.g., ["AllCops", "Exclude"])
    # 2. Merges template content at that location
    # 3. Leaves the rest of the destination unchanged
    #
    # @example Basic usage - merge into existing key
    #   template = <<~YAML
    #     - examples/**/*
    #     - vendor/**/*
    #   YAML
    #
    #   destination = <<~YAML
    #     AllCops:
    #       Exclude:
    #         - tmp/**/*
    #       TargetRubyVersion: 3.2
    #   YAML
    #
    #   merger = PartialTemplateMerger.new(
    #     template: template,
    #     destination: destination,
    #     key_path: ["AllCops", "Exclude"]
    #   )
    #   result = merger.merge
    #
    # @example Adding a new nested key
    #   merger = PartialTemplateMerger.new(
    #     template: "enable",
    #     destination: "AllCops:\n  Exclude: []",
    #     key_path: ["AllCops", "NewCops"],
    #     when_missing: :add
    #   )
    #
    class PartialTemplateMerger
      # Result of a partial template merge
      class Result
        attr_reader :content, :has_key_path, :changed, :stats, :message

        def initialize(content:, has_key_path:, changed:, stats: {}, message: nil)
          @content = content
          @has_key_path = has_key_path
          @changed = changed
          @stats = stats
          @message = message
        end

        def key_path_found?
          has_key_path
        end
      end

      # @return [String] The template content to merge
      attr_reader :template

      # @return [String] The destination content
      attr_reader :destination

      # @return [Array<String, Integer>] Path to the target key (e.g., ["AllCops", "Exclude"])
      attr_reader :key_path

      # @return [Symbol] Merge preference (:template or :destination)
      attr_reader :preference

      # @return [Boolean] Whether to add template items not in destination
      attr_reader :add_missing

      # @return [Boolean] Whether to remove destination items not in template
      attr_reader :remove_missing

      # @return [Symbol] What to do when key path not found (:skip, :add)
      attr_reader :when_missing

      # @return [Boolean] Whether to recursively merge nested structures
      attr_reader :recursive

      # Initialize a PartialTemplateMerger.
      #
      # @param template [String] The template content to merge
      # @param destination [String] The destination content
      # @param key_path [Array<String, Integer>] Path to target key (e.g., ["AllCops", "Exclude"])
      # @param preference [Symbol] Which content wins on conflicts (:template or :destination)
      # @param add_missing [Boolean] Whether to add template items not in destination
      # @param remove_missing [Boolean] Whether to remove destination items not in template
      # @param when_missing [Symbol] Behavior when key path not found (:skip, :add)
      # @param recursive [Boolean] Whether to recursively merge nested structures
      def initialize(
        template:,
        destination:,
        key_path:,
        preference: :destination,
        add_missing: true,
        remove_missing: false,
        when_missing: :skip,
        recursive: true
      )
        @template = template
        @destination = destination
        @key_path = Array(key_path)
        @preference = preference
        @add_missing = add_missing
        @remove_missing = remove_missing
        @when_missing = when_missing
        @recursive = recursive

        validate_key_path!
      end

      # Perform the partial template merge.
      #
      # @return [Result] The merge result
      def merge
        d_analysis = FileAnalysis.new(destination)

        unless d_analysis.valid?
          return Result.new(
            content: destination,
            has_key_path: false,
            changed: false,
            message: "Failed to parse destination: #{d_analysis.errors.join(", ")}",
          )
        end

        # Navigate to the key path
        target_entry = find_key_path(d_analysis)

        if target_entry.nil?
          return handle_missing_key_path(d_analysis)
        end

        # Perform the merge at the found location
        perform_merge_at_path(d_analysis, target_entry)
      end

      private

      def validate_key_path!
        if key_path.empty?
          raise ArgumentError, "key_path cannot be empty"
        end
      end

      # Navigate the YAML structure to find the target key path.
      #
      # @param analysis [FileAnalysis] The parsed YAML
      # @return [MappingEntry, nil] The entry at the key path, or nil if not found
      def find_key_path(analysis)
        current_entries = analysis.statements
        target_entry = nil

        key_path.each_with_index do |key, depth|
          # Find entry matching this key
          entry = current_entries.find do |e|
            e.respond_to?(:key_name) && e.key_name == key
          end

          return nil unless entry

          if depth == key_path.length - 1
            # This is the target entry
            target_entry = entry
          elsif entry.mapping?
            # Navigate deeper
            current_entries = entry.value.mapping_entries(comment_tracker: analysis.comment_tracker).map do |k, v|
              MappingEntry.new(key: k, value: v, lines: analysis.lines, comment_tracker: analysis.comment_tracker)
            end
          else
            # Can't navigate further into non-mapping
            return nil
          end
        end

        target_entry
      end

      # Handle case when key path is not found.
      def handle_missing_key_path(analysis)
        case when_missing
        when :add
          # Add the key path and template content
          new_content = add_key_path_with_content(analysis)
          Result.new(
            content: new_content,
            has_key_path: false,
            changed: true,
            message: "Key path not found, added with template content",
          )
        else
          Result.new(
            content: destination,
            has_key_path: false,
            changed: false,
            message: "Key path not found, skipping",
          )
        end
      end

      # Add the missing key path with template content.
      def add_key_path_with_content(analysis)
        # Parse template to get proper YAML structure
        template_yaml = begin
          ::Psych.safe_load(template)
        rescue
          template
        end

        # Build nested structure from key_path
        result = template_yaml
        key_path.reverse_each do |key|
          result = {key => result}
        end

        # Parse destination and merge
        dest_yaml = begin
          ::Psych.safe_load(destination)
        rescue
          {}
        end
        merged = deep_merge_hash(dest_yaml, result)

        ::Psych.dump(merged).sub(/\A---\n?/, "")
      end

      # Perform merge at the found key path.
      def perform_merge_at_path(analysis, target_entry)
        # Get the value at the target path
        target_value = target_entry.value

        new_content = if target_value.sequence?
          # Merge sequences (arrays)
          merge_sequence_at_path(analysis, target_entry)
        elsif target_value.mapping?
          # Merge mappings
          merge_mapping_at_path(analysis, target_entry)
        else
          # Scalar value - replace based on preference
          merge_scalar_at_path(analysis, target_entry)
        end

        changed = new_content != destination

        Result.new(
          content: new_content,
          has_key_path: true,
          changed: changed,
          message: changed ? "Merged at key path" : "No changes needed",
        )
      end

      # Merge when target is a sequence (array).
      def merge_sequence_at_path(analysis, target_entry)
        # Use SmartMerger for the merge
        # Build a partial template with just this key path
        template_wrapper = build_template_at_path

        merger = SmartMerger.new(
          template_wrapper,
          destination,
          preference: preference,
          add_template_only_nodes: add_missing,
          remove_template_missing_nodes: remove_missing,
          recursive: recursive,
        )

        merger.merge
      end

      # Merge when target is a mapping.
      def merge_mapping_at_path(analysis, target_entry)
        template_wrapper = build_template_at_path

        merger = SmartMerger.new(
          template_wrapper,
          destination,
          preference: preference,
          add_template_only_nodes: add_missing,
          remove_template_missing_nodes: remove_missing,
          recursive: recursive,
        )

        merger.merge
      end

      # Merge when target is a scalar.
      def merge_scalar_at_path(analysis, target_entry)
        if preference == :template
          # Replace scalar with template content
          template_wrapper = build_template_at_path
          merger = SmartMerger.new(
            template_wrapper,
            destination,
            preference: :template,
            add_template_only_nodes: true,
            recursive: false,
          )
          merger.merge
        else
          # Keep destination
          destination
        end
      end

      # Build a complete YAML document with template content at the key path.
      def build_template_at_path
        # Parse template content
        template_content = begin
          ::Psych.safe_load(template)
        rescue
          template
        end

        # Build nested structure
        result = template_content
        key_path.reverse_each do |key|
          result = {key => result}
        end

        ::Psych.dump(result).sub(/\A---\n?/, "")
      end

      # Deep merge two hashes.
      def deep_merge_hash(base, overlay)
        return overlay unless base.is_a?(Hash) && overlay.is_a?(Hash)

        result = base.dup
        overlay.each do |key, value|
          result[key] = if result.key?(key) && result[key].is_a?(Hash) && value.is_a?(Hash)
            deep_merge_hash(result[key], value)
          else
            value
          end
        end
        result
      end
    end
  end
end
