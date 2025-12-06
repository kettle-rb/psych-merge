# frozen_string_literal: true

module Psych
  module Merge
    # Custom YAML emitter that preserves comments and formatting.
    # This class provides utilities for emitting YAML while maintaining
    # the original structure, comments, and style choices.
    #
    # @example Basic usage
    #   emitter = Emitter.new
    #   emitter.emit_mapping_entry(key, value, leading_comments: comments)
    class Emitter
      # @return [Array<String>] Output lines
      attr_reader :lines

      # @return [Integer] Current indentation level
      attr_reader :indent_level

      # @return [Integer] Spaces per indent level
      attr_reader :indent_size

      # Initialize a new emitter
      #
      # @param indent_size [Integer] Number of spaces per indent level
      def initialize(indent_size: 2)
        @lines = []
        @indent_level = 0
        @indent_size = indent_size
      end

      # Emit a comment line
      #
      # @param text [String] Comment text (without #)
      # @param inline [Boolean] Whether this is an inline comment
      def emit_comment(text, inline: false)
        if inline
          # Inline comments are appended to the last line
          return if @lines.empty?

          @lines[-1] = "#{@lines[-1]} # #{text}"
        else
          @lines << "#{current_indent}# #{text}"
        end
      end

      # Emit leading comments
      #
      # @param comments [Array<Hash>] Comment hashes from CommentTracker
      def emit_leading_comments(comments)
        comments.each do |comment|
          # Preserve original indentation from comment
          indent = " " * (comment[:indent] || 0)
          @lines << "#{indent}# #{comment[:text]}"
        end
      end

      # Emit a blank line
      def emit_blank_line
        @lines << ""
      end

      # Emit a scalar value
      #
      # @param key [String] Key name
      # @param value [String] Value
      # @param style [Symbol] Style (:plain, :single_quoted, :double_quoted, :literal, :folded)
      # @param inline_comment [String, nil] Optional inline comment
      def emit_scalar_entry(key, value, style: :plain, inline_comment: nil)
        formatted_value = format_scalar(value, style)
        line = "#{current_indent}#{key}: #{formatted_value}"
        line += " # #{inline_comment}" if inline_comment
        @lines << line
      end

      # Emit a mapping start (for nested mappings)
      #
      # @param key [String] Key name
      # @param anchor [String, nil] Anchor name (without &)
      def emit_mapping_start(key, anchor: nil)
        anchor_str = anchor ? " &#{anchor}" : ""
        @lines << "#{current_indent}#{key}:#{anchor_str}"
        @indent_level += 1
      end

      # Emit a mapping end
      def emit_mapping_end
        @indent_level -= 1 if @indent_level > 0
      end

      # Emit a sequence start
      #
      # @param key [String, nil] Key name (nil for inline sequence)
      # @param anchor [String, nil] Anchor name
      def emit_sequence_start(key, anchor: nil)
        if key
          anchor_str = anchor ? " &#{anchor}" : ""
          @lines << "#{current_indent}#{key}:#{anchor_str}"
          @indent_level += 1
        end
      end

      # Emit a sequence item
      #
      # @param value [String] Item value
      # @param inline_comment [String, nil] Optional inline comment
      def emit_sequence_item(value, inline_comment: nil)
        line = "#{current_indent}- #{value}"
        line += " # #{inline_comment}" if inline_comment
        @lines << line
      end

      # Emit a sequence end
      def emit_sequence_end
        @indent_level -= 1 if @indent_level > 0
      end

      # Emit an alias reference
      #
      # @param key [String] Key name
      # @param anchor [String] Anchor name being referenced (without *)
      def emit_alias(key, anchor)
        @lines << "#{current_indent}#{key}: *#{anchor}"
      end

      # Emit a merge key with alias
      #
      # @param anchor [String] Anchor name to merge (without *)
      def emit_merge_key(anchor)
        @lines << "#{current_indent}<<: *#{anchor}"
      end

      # Emit raw lines (for preserving existing content)
      #
      # @param raw_lines [Array<String>] Lines to emit as-is
      def emit_raw_lines(raw_lines)
        raw_lines.each { |line| @lines << line.chomp }
      end

      # Get the output as a single string
      #
      # @return [String]
      def to_yaml
        content = @lines.join("\n")
        content += "\n" unless content.empty? || content.end_with?("\n")
        content
      end

      # Clear the output
      def clear
        @lines = []
        @indent_level = 0
      end

      private

      def current_indent
        " " * (@indent_level * @indent_size)
      end

      def format_scalar(value, style)
        case style
        when :single_quoted
          "'#{escape_single_quotes(value)}'"
        when :double_quoted
          "\"#{escape_double_quotes(value)}\""
        when :literal
          # Literal scalars need special handling
          "|\n#{indent_multiline(value)}"
        when :folded
          # Folded scalars need special handling
          ">\n#{indent_multiline(value)}"
        else
          # Plain style - check if quoting is needed
          needs_quoting?(value) ? "\"#{escape_double_quotes(value)}\"" : value.to_s
        end
      end

      def escape_single_quotes(value)
        value.to_s.gsub("'", "''")
      end

      def escape_double_quotes(value)
        value.to_s
          .gsub("\\", "\\\\")
          .gsub("\"", "\\\"")
          .gsub("\n", "\\n")
          .gsub("\t", "\\t")
      end

      def indent_multiline(value)
        value.to_s.lines.map { |line| "#{current_indent}  #{line.chomp}" }.join("\n")
      end

      def needs_quoting?(value)
        str = value.to_s

        # Empty string needs quotes
        return true if str.empty?

        # Check for special characters that need quoting
        return true if str =~ /^[&*!|>'"%@`]/
        return true if str =~ /[:#\[\]{}?,]/
        return true if str =~ /^\s|\s$/
        return true if str =~ /\n/

        # Check for boolean/null-like values
        return true if %w[true false yes no on off null ~].include?(str.downcase)

        # Check for numeric values that should stay as strings
        return true if str =~ /^\d+$/ && str.start_with?("0") && str.length > 1

        false
      end
    end
  end
end
