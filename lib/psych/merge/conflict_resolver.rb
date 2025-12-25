# frozen_string_literal: true

module Psych
  module Merge
    # Resolves conflicts between template and destination YAML content
    # using structural signatures and configurable preferences.
    #
    # Inherits from Ast::Merge::ConflictResolverBase using the :batch strategy,
    # which resolves all conflicts at once using signature maps.
    #
    # @example Basic usage
    #   resolver = ConflictResolver.new(template_analysis, dest_analysis)
    #   resolver.resolve(result)
    #
    # @see Ast::Merge::ConflictResolverBase
    class ConflictResolver < Ast::Merge::ConflictResolverBase
      # Creates a new ConflictResolver
      #
      # @param template_analysis [FileAnalysis] Analyzed template file
      # @param dest_analysis [FileAnalysis] Analyzed destination file
      # @param preference [Symbol] Which version to prefer when
      #   nodes have matching signatures:
      #   - :destination (default) - Keep destination version (customizations)
      #   - :template - Use template version (updates)
      # @param add_template_only_nodes [Boolean] Whether to add nodes only in template
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching
      # @param options [Hash] Additional options for forward compatibility
      def initialize(template_analysis, dest_analysis, preference: :destination, add_template_only_nodes: false, match_refiner: nil, **options)
        super(
          strategy: :batch,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          add_template_only_nodes: add_template_only_nodes,
          match_refiner: match_refiner,
          **options
        )
      end

      protected

      # Resolve conflicts and populate the result
      #
      # @param result [MergeResult] Result object to populate
      def resolve_batch(result)
        DebugLogger.time("ConflictResolver#resolve") do
          template_nodes = @template_analysis.statements
          dest_nodes = @dest_analysis.statements

          # Build signature maps
          template_by_sig = build_signature_map(template_nodes, @template_analysis)
          dest_by_sig = build_signature_map(dest_nodes, @dest_analysis)

          # Build refined matches for nodes that don't match by signature
          @refined_matches = build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)

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
            result,
          )

          DebugLogger.debug("Conflict resolution complete", {
            template_nodes: template_nodes.size,
            dest_nodes: dest_nodes.size,
            result_lines: result.line_count,
          })
        end
      end

      private

      # Build a map of refined matches from template node to destination node.
      # Uses the match_refiner to find additional pairings for nodes that didn't match by signature.
      #
      # @param template_nodes [Array] Template nodes
      # @param dest_nodes [Array] Destination nodes
      # @param template_by_sig [Hash] Template signature map
      # @param dest_by_sig [Hash] Destination signature map
      # @return [Hash] Map of template node to destination node
      def build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)
        return {} unless @match_refiner

        # Find unmatched nodes
        matched_template_sigs = template_by_sig.keys & dest_by_sig.keys
        unmatched_t_nodes = template_nodes.reject do |n|
          sig = @template_analysis.generate_signature(n)
          sig && matched_template_sigs.include?(sig)
        end
        unmatched_d_nodes = dest_nodes.reject do |n|
          sig = @dest_analysis.generate_signature(n)
          sig && matched_template_sigs.include?(sig)
        end

        return {} if unmatched_t_nodes.empty? || unmatched_d_nodes.empty?

        # Call the refiner
        matches = @match_refiner.call(unmatched_t_nodes, unmatched_d_nodes, {
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
        })

        # Build result map: template node -> dest node
        matches.each_with_object({}) do |match, h|
          h[match.template_node] = match.dest_node
        end
      end

      def merge_nodes(template_nodes, dest_nodes, template_by_sig, dest_by_sig, processed_template_sigs, processed_dest_sigs, result)
        # Determine the output order based on preference
        # We'll iterate through destination nodes first (to preserve dest order for matches)
        # then add any template-only nodes if configured

        # Build reverse lookup from dest_node to template_node for refined matches
        refined_dest_to_template = @refined_matches.invert

        # First pass: Process destination nodes and find matches
        dest_nodes.each do |dest_node|
          dest_sig = @dest_analysis.generate_signature(dest_node)

          # Freeze blocks from destination are always preserved
          if freeze_node?(dest_node)
            add_node_to_result(dest_node, result, :destination, MergeResult::DECISION_FREEZE_BLOCK)
            processed_dest_sigs << dest_sig if dest_sig
            next
          end

          # Check for signature match first
          if dest_sig && template_by_sig[dest_sig]
            # Found matching node in template
            template_info = template_by_sig[dest_sig].first
            template_node = template_info[:node]

            # Decide which to keep based on preference
            if @preference == :destination
              add_node_to_result(dest_node, result, :destination, MergeResult::DECISION_KEPT_DEST)
            else
              add_node_to_result(template_node, result, :template, MergeResult::DECISION_KEPT_TEMPLATE)
            end

            processed_dest_sigs << dest_sig
            processed_template_sigs << dest_sig
          elsif refined_dest_to_template.key?(dest_node)
            # Found refined match
            template_node = refined_dest_to_template[dest_node]
            template_sig = @template_analysis.generate_signature(template_node)

            # Decide which to keep based on preference
            if @preference == :destination
              add_node_to_result(dest_node, result, :destination, MergeResult::DECISION_KEPT_DEST)
            else
              add_node_to_result(template_node, result, :template, MergeResult::DECISION_KEPT_TEMPLATE)
            end

            processed_dest_sigs << dest_sig if dest_sig
            processed_template_sigs << template_sig if template_sig
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
          next if freeze_node?(template_node)

          # Add template-only node
          add_node_to_result(template_node, result, :template, MergeResult::DECISION_ADDED)
          processed_template_sigs << template_sig if template_sig
        end
      end

      def add_node_to_result(node, result, source, decision)
        if freeze_node?(node)
          result.add_freeze_block(node)
        elsif node.is_a?(MappingEntry)
          result.add_mapping_entry(node, decision: decision, source: source)
        elsif node.is_a?(NodeWrapper)
          add_wrapper_to_result(node, result, source, decision)
        else
          DebugLogger.debug("Unknown node type", {node_type: node.class.name})
        end
      end

      def add_wrapper_to_result(wrapper, result, source, decision)
        return unless wrapper.start_line && wrapper.end_line

        analysis = (source == :template) ? @template_analysis : @dest_analysis

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
