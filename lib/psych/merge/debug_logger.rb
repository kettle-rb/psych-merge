# frozen_string_literal: true

module Psych
  module Merge
    # Debug logging utility for Psych::Merge.
    # Extends the base Ast::Merge::DebugLogger with Psych-specific configuration.
    #
    # @example Enable debug logging
    #   ENV['PSYCH_MERGE_DEBUG'] = '1'
    #   DebugLogger.debug("Processing node", {type: "mapping", line: 5})
    #
    # @example Disable debug logging (default)
    #   DebugLogger.debug("This won't be printed", {})
    module DebugLogger
      extend Ast::Merge::DebugLogger

      # Use the base BENCHMARK_AVAILABLE constant
      BENCHMARK_AVAILABLE = Ast::Merge::DebugLogger::BENCHMARK_AVAILABLE

      # Psych-specific configuration
      ENV_VAR_NAME = "PSYCH_MERGE_DEBUG"
      LOG_PREFIX = "[Psych::Merge]"

      # Check if debug mode is enabled
      #
      # @return [Boolean]
      def self.enabled?
        ENV[ENV_VAR_NAME] == "1" || ENV[ENV_VAR_NAME] == "true"
      end

      # Log a debug message with optional context
      #
      # @param message [String] The debug message
      # @param context [Hash] Optional context to include
      def self.debug(message, context = {})
        return unless enabled?

        output = "#{LOG_PREFIX} #{message}"
        output += " #{context.inspect}" unless context.empty?
        warn output
      end

      # Log an info message (always shown when debug is enabled)
      #
      # @param message [String] The info message
      def self.info(message)
        return unless enabled?

        warn "#{LOG_PREFIX} INFO] #{message}"
      end

      # Log a warning message (always shown)
      #
      # @param message [String] The warning message
      def self.warning(message)
        warn "#{LOG_PREFIX} WARNING] #{message}"
      end

      # Time a block and log the duration
      # Delegates to base implementation with Psych-specific logging
      #
      # @param operation [String] Name of the operation
      # @yield The block to time
      # @return [Object] The result of the block
      def self.time(operation)
        unless enabled?
          return yield
        end

        unless BENCHMARK_AVAILABLE
          warning("Benchmark gem not available - timing disabled for: #{operation}")
          return yield
        end

        debug("Starting: #{operation}")
        result = nil
        timing = Benchmark.measure { result = yield }
        debug("Completed: #{operation}", {
          real_ms: (timing.real * 1000).round(2),
          user_ms: (timing.utime * 1000).round(2),
          system_ms: (timing.stime * 1000).round(2),
        })
        result
      end

      # Log node information with Psych-specific handling
      #
      # @param node [Object] Node to log information about
      # @param label [String] Label for the node
      def self.log_node(node, label: "Node")
        return unless enabled?

        info = case node
        when FreezeNode
          {type: "FreezeNode", lines: "#{node.start_line}..#{node.end_line}"}
        when MappingEntry
          {type: "MappingEntry", key: node.key_name, lines: "#{node.start_line}..#{node.end_line}"}
        when NodeWrapper
          {type: node.node.class.name.split("::").last, lines: "#{node.start_line}..#{node.end_line}"}
        else
          {type: node.class.name}
        end

        debug(label, info)
      end
    end
  end
end
