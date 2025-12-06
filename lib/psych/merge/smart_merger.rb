# frozen_string_literal: true

module Psych
  module Merge
    # Main entry point for intelligent YAML file merging.
    # SmartMerger orchestrates the merge process using FileAnalysis,
    # ConflictResolver, and MergeResult to merge two YAML files intelligently.
    #
    # @example Basic merge (destination customizations preserved)
    #   merger = SmartMerger.new(template_yaml, dest_yaml)
    #   result = merger.merge
    #   File.write("output.yml", result)
    #
    # @example Template updates win
    #   merger = SmartMerger.new(
    #     template_yaml,
    #     dest_yaml,
    #     signature_match_preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #
    # @example With custom signature generator
    #   sig_gen = ->(node) {
    #     if node.is_a?(MappingEntry) && node.key_name == "version"
    #       [:special_version, node.key_name]
    #     else
    #       node # Fall through to default
    #     end
    #   }
    #   merger = SmartMerger.new(template, dest, signature_generator: sig_gen)
    class SmartMerger
      # @return [FileAnalysis] Analysis of the template file
      attr_reader :template_analysis

      # @return [FileAnalysis] Analysis of the destination file
      attr_reader :dest_analysis

      # @return [ConflictResolver] Resolver for handling conflicts
      attr_reader :resolver

      # @return [MergeResult] Result of the merge operation
      attr_reader :result

      # @return [Symbol] Preference for signature matches
      attr_reader :signature_match_preference

      # @return [Boolean] Whether to add template-only nodes
      attr_reader :add_template_only_nodes

      # @return [String] Token used for freeze blocks
      attr_reader :freeze_token

      # Creates a new SmartMerger for intelligent YAML file merging.
      #
      # @param template_content [String] Template YAML source code
      # @param dest_content [String] Destination YAML source code
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param signature_match_preference [Symbol] Which version to prefer when
      #   nodes have matching signatures:
      #   - :destination (default) - Keep destination version (customizations)
      #   - :template - Use template version (updates)
      # @param add_template_only_nodes [Boolean] Whether to add nodes only in template
      # @param freeze_token [String] Token for freeze block markers
      #
      # @raise [TemplateParseError] If template has syntax errors
      # @raise [DestinationParseError] If destination has syntax errors
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        signature_match_preference: :destination,
        add_template_only_nodes: false,
        freeze_token: FileAnalysis::DEFAULT_FREEZE_TOKEN
      )
        @signature_match_preference = signature_match_preference
        @add_template_only_nodes = add_template_only_nodes
        @freeze_token = freeze_token

        # Analyze both files
        @template_analysis = FileAnalysis.new(
          template_content,
          freeze_token: freeze_token,
          signature_generator: signature_generator
        )

        @dest_analysis = FileAnalysis.new(
          dest_content,
          freeze_token: freeze_token,
          signature_generator: signature_generator
        )

        # Validate parsing
        validate_parsing!

        # Create resolver
        @resolver = ConflictResolver.new(
          @template_analysis,
          @dest_analysis,
          signature_match_preference: signature_match_preference,
          add_template_only_nodes: add_template_only_nodes
        )

        # Initialize result
        @result = MergeResult.new

        DebugLogger.debug("SmartMerger initialized", {
          template_valid: @template_analysis.valid?,
          dest_valid: @dest_analysis.valid?,
          preference: signature_match_preference,
          add_template_only: add_template_only_nodes,
        })
      end

      # Perform the merge and return the result as a YAML string.
      #
      # @return [String] Merged YAML content
      def merge
        DebugLogger.time("SmartMerger#merge") do
          @resolver.resolve(@result)
          @result.to_yaml
        end
      end

      # Perform the merge and return detailed results including debug info.
      #
      # @return [Hash] Hash containing :content, :statistics, :decisions
      def merge_with_debug
        content = merge

        {
          content: content,
          statistics: @result.statistics,
          decisions: @result.decision_summary,
          template_analysis: {
            valid: @template_analysis.valid?,
            nodes: @template_analysis.nodes.size,
            freeze_blocks: @template_analysis.freeze_blocks.size,
          },
          dest_analysis: {
            valid: @dest_analysis.valid?,
            nodes: @dest_analysis.nodes.size,
            freeze_blocks: @dest_analysis.freeze_blocks.size,
          },
        }
      end

      # Check if both files were parsed successfully.
      #
      # @return [Boolean]
      def valid?
        @template_analysis.valid? && @dest_analysis.valid?
      end

      # Get any parse errors from template or destination.
      #
      # @return [Array] Array of errors
      def errors
        errors = []
        errors.concat(@template_analysis.errors.map { |e| {source: :template, error: e} })
        errors.concat(@dest_analysis.errors.map { |e| {source: :destination, error: e} })
        errors
      end

      private

      def validate_parsing!
        unless @template_analysis.valid?
          raise TemplateParseError.new(
            "Template YAML has syntax errors",
            content: @template_analysis.source,
            errors: @template_analysis.errors
          )
        end

        unless @dest_analysis.valid?
          raise DestinationParseError.new(
            "Destination YAML has syntax errors",
            content: @dest_analysis.source,
            errors: @dest_analysis.errors
          )
        end
      end
    end
  end
end
