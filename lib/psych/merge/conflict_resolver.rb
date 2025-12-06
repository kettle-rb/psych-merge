# frozen_string_literal: true

module Psych
  module Merge
    # Resolves conflicts between template and destination YAML content
    # using structural signatures and configurable preferences.
    #
    # @example Basic usage
    #   resolver = ConflictResolver.new(template_analysis, dest_analysis)
    #   resolver.resolve(result)
    class ConflictResolver
      # @return [FileAnalysis] Analysis of the template file
      attr_reader :template_analysis

      # @return [FileAnalysis] Analysis of the destination file
      attr_reader :dest_analysis

      # @return [Symbol] Preference for signature matches (:template or :destination)
      attr_reader :signature_match_preference

      # @return [Boolean] Whether to add template-only nodes
      attr_reader :add_template_only_nodes

      # Creates a new ConflictResolver
      #
      # @param template_analysis [FileAnalysis] Analyzed template file
      # @param dest_analysis [FileAnalysis] Analyzed destination file
      # @param signature_match_preference [Symbol] Which version to prefer when
      #   nodes have matching signatures:
      #   - :destination (default) - Keep destination version (customizations)
      #   - :template - Use template version (updates)
      # @param add_template_only_nodes [Boolean] Whether to add nodes only in template
      def initialize(template_analysis, dest_analysis, signature_match_preference: :destination, add_template_only_nodes: false)
        @template_analysis = template_analysis
        @dest_analysis = dest_analysis
        @signature_match_preference = signature_match_preference
        @add_template_only_nodes = add_template_only_nodes
      end

      # Resolve conflicts and populate the result
      #
      # @param result [MergeResult] Result object to populate
      def resolve(result)
        DebugLogger.time("ConflictResolver#resolve") do
          template_nodes = @template_analysis.nodes
          dest_nodes = @dest_analysis.nodes

          # Build signature maps
          template_by_sig = build_signature_map(template_nodes, @template_analysis)
          dest_by_sig = build_signature_map(dest_nodes, @dest_analysis)

          # Track which nodes have been processed
          processed_template_sigs = ::Set.new
          processed_dest_sigs = ::Set.new

          # Process nodes in order, preferring destination order when nodes match
          merge_nodes(
            template_nodes,
            dest_nodes,
            template_by_sig,
            dest_by_sig,
            processed_template_sigs,
            processed_dest_sigs,
            result
          )

          DebugLogger.debug("Conflict resolution complete", {
            template_nodes: template_nodes.size,
            dest_nodes: dest_nodes.size,
            result_lines: result.line_count,
          })
        end
      end

      private

      def build_signature_map(nodes, analysis)
        map = {}
        nodes.each_with_index do |node, idx|
          sig = analysis.generate_signature(node)
          next unless sig

          map[sig] ||= []
          map[sig] << {node: node, index: idx}
        end
        map
      end

      def merge_nodes(template_nodes, dest_nodes, template_by_sig, dest_by_sig, processed_template_sigs, processed_dest_sigs, result)
        # Determine the output order based on preference
        # We'll iterate through destination nodes first (to preserve dest order for matches)
        # then add any template-only nodes if configured

        # First pass: Process destination nodes and find matches
        dest_nodes.each do |dest_node|
          dest_sig = @dest_analysis.generate_signature(dest_node)

          # Freeze blocks from destination are always preserved
          if dest_node.freeze_node?
            add_node_to_result(dest_node, result, :destination, MergeResult::DECISION_FREEZE_BLOCK)
            processed_dest_sigs << dest_sig if dest_sig
            next
          end

          if dest_sig && template_by_sig[dest_sig]
            # Found matching node in template
            template_info = template_by_sig[dest_sig].first
            template_node = template_info[:node]

            # Decide which to keep based on preference
            if @signature_match_preference == :destination
              add_node_to_result(dest_node, result, :destination, MergeResult::DECISION_KEPT_DEST)
            else
              add_node_to_result(template_node, result, :template, MergeResult::DECISION_KEPT_TEMPLATE)
            end

            processed_dest_sigs << dest_sig
            processed_template_sigs << dest_sig
          else
            # Destination-only node - always keep
            add_node_to_result(dest_node, result, :destination, MergeResult::DECISION_KEPT_DEST)
            processed_dest_sigs << dest_sig if dest_sig
          end
        end

        # Second pass: Add template-only nodes if configured
        return unless @add_template_only_nodes

        template_nodes.each do |template_node|
          template_sig = @template_analysis.generate_signature(template_node)

          # Skip if already processed (matched with dest)
          next if template_sig && processed_template_sigs.include?(template_sig)

          # Skip freeze blocks from template (they shouldn't exist, but just in case)
          next if template_node.freeze_node?

          # Add template-only node
          add_node_to_result(template_node, result, :template, MergeResult::DECISION_ADDED)
          processed_template_sigs << template_sig if template_sig
        end
      end

      def add_node_to_result(node, result, source, decision)
        case node
        when FreezeNode
          result.add_freeze_block(node)
        when MappingEntry
          result.add_mapping_entry(node, decision: decision, source: source)
        when NodeWrapper
          add_wrapper_to_result(node, result, source, decision)
        else
          DebugLogger.debug("Unknown node type", {node_type: node.class.name})
        end
      end

      def add_wrapper_to_result(wrapper, result, source, decision)
        return unless wrapper.start_line && wrapper.end_line

        analysis = source == :template ? @template_analysis : @dest_analysis

        # Include leading comments
        leading = analysis.comment_tracker.leading_comments_before(wrapper.start_line)
        leading.each do |comment|
          result.add_line(comment[:raw], decision: decision, source: source, original_line: comment[:line])
        end

        # Add the node content
        (wrapper.start_line..wrapper.end_line).each do |line_num|
          line = analysis.line_at(line_num)
          next unless line

          result.add_line(line.chomp, decision: decision, source: source, original_line: line_num)
        end
      end
    end
  end
end
