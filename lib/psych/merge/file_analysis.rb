# frozen_string_literal: true

module Psych
  module Merge
    # Analyzes YAML file structure, extracting nodes, comments, and freeze blocks.
    # This is the main analysis class that prepares YAML content for merging.
    #
    # @example Basic usage
    #   analysis = FileAnalysis.new(yaml_source)
    #   analysis.valid? # => true
    #   analysis.nodes # => [NodeWrapper, FreezeNode, ...]
    #   analysis.freeze_blocks # => [FreezeNode, ...]
    class FileAnalysis
      # Default freeze token for identifying freeze blocks
      DEFAULT_FREEZE_TOKEN = "psych-merge"

      # @return [String] Source YAML content
      attr_reader :source

      # @return [Array<String>] Lines of source
      attr_reader :lines

      # @return [String] Token used to mark freeze blocks
      attr_reader :freeze_token

      # @return [Proc, nil] Custom signature generator
      attr_reader :signature_generator

      # @return [CommentTracker] Comment tracker for this file
      attr_reader :comment_tracker

      # @return [Psych::Nodes::Stream, nil] Parsed AST
      attr_reader :ast

      # @return [Array] Parse errors if any
      attr_reader :errors

      # Initialize file analysis
      #
      # @param source [String] YAML source code to analyze
      # @param freeze_token [String] Token for freeze block markers
      # @param signature_generator [Proc, nil] Custom signature generator
      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil)
        @source = source
        @lines = source.lines.map(&:chomp)
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        @errors = []

        # Initialize comment tracking
        @comment_tracker = CommentTracker.new(source)

        # Parse the YAML
        DebugLogger.time("FileAnalysis#parse_yaml") { parse_yaml }

        # Extract freeze blocks and integrate with nodes
        @freeze_blocks = extract_freeze_blocks
        @nodes = integrate_nodes_and_freeze_blocks

        DebugLogger.debug("FileAnalysis initialized", {
          signature_generator: signature_generator ? "custom" : "default",
          nodes_count: @nodes.size,
          freeze_blocks: @freeze_blocks.size,
          valid: valid?,
        })
      end

      # Check if parse was successful
      # @return [Boolean]
      def valid?
        @errors.empty? && !@ast.nil?
      end

      # Get all top-level nodes (wrapped Psych nodes and FreezeNodes)
      # @return [Array<NodeWrapper, FreezeNode>]
      attr_reader :nodes

      # Get all freeze blocks
      # @return [Array<FreezeNode>]
      attr_reader :freeze_blocks

      # Check if a line is within a freeze block
      # @param line_num [Integer] 1-based line number
      # @return [Boolean]
      def in_freeze_block?(line_num)
        @freeze_blocks.any? { |fb| fb.location.cover?(line_num) }
      end

      # Get the freeze block containing the given line
      # @param line_num [Integer] 1-based line number
      # @return [FreezeNode, nil]
      def freeze_block_at(line_num)
        @freeze_blocks.find { |fb| fb.location.cover?(line_num) }
      end

      # Get signature for a node at given index
      # @param index [Integer] Node index
      # @return [Array, nil]
      def signature_at(index)
        return nil if index < 0 || index >= @nodes.length

        generate_signature(@nodes[index])
      end

      # Generate signature for a node
      # @param node [NodeWrapper, FreezeNode] Node to generate signature for
      # @return [Array, nil]
      def generate_signature(node)
        result = if @signature_generator
          custom_result = @signature_generator.call(node)
          if custom_result.is_a?(NodeWrapper) || custom_result.is_a?(FreezeNode) || custom_result.is_a?(MappingEntry)
            # Fall through to default computation
            compute_node_signature(custom_result)
          else
            custom_result
          end
        else
          compute_node_signature(node)
        end

        DebugLogger.debug("Generated signature", {
          node_type: node.class.name.split("::").last,
          signature: result,
          generator: @signature_generator ? "custom" : "default",
        }) if result

        result
      end

      # Get normalized line content (stripped)
      # @param line_num [Integer] 1-based line number
      # @return [String, nil]
      def normalized_line(line_num)
        return nil if line_num < 1 || line_num > @lines.length

        @lines[line_num - 1].strip
      end

      # Get raw line content
      # @param line_num [Integer] 1-based line number
      # @return [String, nil]
      def line_at(line_num)
        return nil if line_num < 1 || line_num > @lines.length

        @lines[line_num - 1]
      end

      # Get mapping entries from the root document
      # @return [Array<Array(NodeWrapper, NodeWrapper)>]
      def root_mapping_entries
        return [] unless valid? && @ast.children&.any?

        doc = @ast.children.first
        return [] unless doc.is_a?(::Psych::Nodes::Document)

        root = doc.children&.first
        return [] unless root.is_a?(::Psych::Nodes::Mapping)

        root_wrapper = NodeWrapper.new(root, lines: @lines)
        root_wrapper.mapping_entries(comment_tracker: @comment_tracker)
      end

      # Get the root node of the first document
      # @return [NodeWrapper, nil]
      def root_node
        return nil unless valid? && @ast.children&.any?

        doc = @ast.children.first
        return nil unless doc.is_a?(::Psych::Nodes::Document)

        root = doc.children&.first
        return nil unless root

        NodeWrapper.new(root, lines: @lines)
      end

      private

      def parse_yaml
        @ast = ::Psych.parse_stream(@source)
      rescue ::Psych::SyntaxError => e
        @errors << e
        @ast = nil
      end

      def extract_freeze_blocks
        freeze_regex = /^\s*#\s*#{Regexp.escape(@freeze_token)}:freeze\s*$/
        unfreeze_regex = /^\s*#\s*#{Regexp.escape(@freeze_token)}:unfreeze\s*$/

        freeze_starts = []
        freeze_ends = []

        @lines.each_with_index do |line, idx|
          line_num = idx + 1
          if line =~ freeze_regex
            freeze_starts << {line: line_num, marker: line}
          elsif line =~ unfreeze_regex
            freeze_ends << {line: line_num, marker: line}
          end
        end

        # Match freeze starts with ends
        blocks = []
        freeze_starts.each do |start_info|
          # Find the next unfreeze after this freeze
          matching_end = freeze_ends.find { |e| e[:line] > start_info[:line] }
          next unless matching_end

          # Remove used end marker
          freeze_ends.delete(matching_end)

          blocks << FreezeNode.new(
            start_line: start_info[:line],
            end_line: matching_end[:line],
            lines: @lines,
            start_marker: start_info[:marker],
            end_marker: matching_end[:marker]
          )
        end

        blocks.sort_by(&:start_line)
      end

      def integrate_nodes_and_freeze_blocks
        return @freeze_blocks unless valid? && @ast.children&.any?

        all_nodes = []
        doc = @ast.children.first
        return @freeze_blocks unless doc.is_a?(::Psych::Nodes::Document)

        root = doc.children&.first
        return @freeze_blocks unless root

        # For mappings, extract key-value pairs as individual nodes
        if root.is_a?(::Psych::Nodes::Mapping)
          root_wrapper = NodeWrapper.new(root, lines: @lines)
          entries = root_wrapper.mapping_entries(comment_tracker: @comment_tracker)

          entries.each do |key_wrapper, value_wrapper|
            key_line = key_wrapper.start_line || 1

            # Check if this entry is inside a freeze block
            if in_freeze_block?(key_line)
              # Entry is in freeze block, will be handled by freeze block
              next
            end

            # Check if there's a freeze block that should come before this entry
            @freeze_blocks.each do |fb|
              if fb.start_line < key_line && !all_nodes.include?(fb)
                all_nodes << fb
              end
            end

            # Add the key-value pair as a mapping entry
            all_nodes << MappingEntry.new(
              key: key_wrapper,
              value: value_wrapper,
              lines: @lines,
              comment_tracker: @comment_tracker
            )
          end

          # Add any remaining freeze blocks at the end
          @freeze_blocks.each do |fb|
            all_nodes << fb unless all_nodes.include?(fb)
          end
        else
          # For sequences or scalars at root, wrap the whole thing
          all_nodes << NodeWrapper.new(root, lines: @lines)

          # Integrate freeze blocks
          @freeze_blocks.each do |fb|
            all_nodes << fb unless all_nodes.include?(fb)
          end
        end

        all_nodes.sort_by { |n| n.start_line || 0 }
      end

      def compute_node_signature(node)
        case node
        when FreezeNode
          node.signature
        when MappingEntry
          [:mapping_entry, node.key_name]
        when NodeWrapper
          node.signature
        else
          nil
        end
      end
    end

    # Represents a key-value entry in a YAML mapping
    class MappingEntry
      # @return [NodeWrapper] The key node
      attr_reader :key

      # @return [NodeWrapper] The value node
      attr_reader :value

      # @return [Array<String>] Source lines
      attr_reader :lines

      # @return [CommentTracker] Comment tracker
      attr_reader :comment_tracker

      # @param key [NodeWrapper] Key wrapper
      # @param value [NodeWrapper] Value wrapper
      # @param lines [Array<String>] Source lines
      # @param comment_tracker [CommentTracker] Comment tracker
      def initialize(key:, value:, lines:, comment_tracker:)
        @key = key
        @value = value
        @lines = lines
        @comment_tracker = comment_tracker
      end

      # Get the key name as a string
      # @return [String, nil]
      def key_name
        @key.value
      end

      # Get the start line (from the key)
      # @return [Integer, nil]
      def start_line
        # Include leading comments in start line
        leading = @comment_tracker.leading_comments_before(@key.start_line || 1)
        if leading.any?
          leading.first[:line]
        else
          @key.start_line
        end
      end

      # Get the end line (from the value)
      # @return [Integer, nil]
      def end_line
        @value.end_line || @key.end_line
      end

      # Get the line range
      # @return [Range, nil]
      def line_range
        return nil unless start_line && end_line

        start_line..end_line
      end

      # Get the content for this entry
      # @return [String]
      def content
        return "" unless start_line && end_line

        (start_line..end_line).map { |ln| @lines[ln - 1] }.compact.join("\n")
      end

      # Generate signature for this entry
      # @return [Array]
      def signature
        [:mapping_entry, key_name]
      end

      # Location-like object for compatibility
      def location
        @location ||= FreezeNode::Location.new(start_line, end_line)
      end

      # Check if this is a freeze node
      # @return [Boolean]
      def freeze_node?
        false
      end

      # Check if this is a mapping
      # @return [Boolean]
      def mapping?
        @value.mapping?
      end

      # Check if this is a sequence
      # @return [Boolean]
      def sequence?
        @value.sequence?
      end

      # Check if this is a scalar
      # @return [Boolean]
      def scalar?
        @value.scalar?
      end

      # Get the anchor if present
      # @return [String, nil]
      def anchor
        @value.anchor
      end

      # String representation
      # @return [String]
      def inspect
        "#<#{self.class.name} key=#{key_name.inspect} lines=#{start_line}..#{end_line}>"
      end
    end
  end
end
