# Psych::Merge

[![Version](https://img.shields.io/gem/v/psych-merge.svg)](https://rubygems.org/gems/psych-merge)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Ruby](https://img.shields.io/badge/Ruby-3.2+-red.svg)](https://www.ruby-lang.org)

Intelligent YAML file merging using Psych AST analysis. Psych::Merge provides smart YAML file merging that preserves comments, anchors/aliases, and supports freeze blocks for protecting destination content.

Perfect for:
- Merging configuration templates with customized destination files
- Updating YAML configs while preserving local customizations
- Managing multi-environment configuration files

## Features

- **Structural Merging**: Merges YAML files by understanding the structure, not just text
- **Comment Preservation**: Preserves comments in merged output
- **Anchor/Alias Support**: Properly handles YAML anchors (`&name`) and aliases (`*name`)
- **Freeze Blocks**: Protect sections of your destination file from being overwritten
- **Configurable Preferences**: Choose whether template or destination values win
- **Template-Only Node Control**: Optionally add new keys from templates

## Requirements

- Ruby >= 3.2.0
- Psych >= 5.0.1 (bundled with Ruby 3.2+)

## Installation

Add to your Gemfile:

```ruby
gem "psych-merge"
```

Or install directly:

```bash
gem install psych-merge
```

## Usage

### Basic Merge

```ruby
require "psych/merge"

template = <<~YAML
  database:
    host: localhost
    port: 5432
  cache:
    enabled: true
YAML

destination = <<~YAML
  database:
    host: production.example.com
    port: 5432
  cache:
    enabled: false
    ttl: 3600
YAML

merger = Psych::Merge::SmartMerger.new(template, destination)
result = merger.merge

# Result keeps destination values:
# database:
#   host: production.example.com
#   port: 5432
# cache:
#   enabled: false
#   ttl: 3600
```

### Configuration Options

#### Signature Match Preference

Control which version wins when both files have the same key:

```ruby
# Template wins (useful for version files, canonical configs)
merger = Psych::Merge::SmartMerger.new(
  template,
  destination,
  signature_match_preference: :template
)

# Destination wins (default - preserves customizations)
merger = Psych::Merge::SmartMerger.new(
  template,
  destination,
  signature_match_preference: :destination
)
```

#### Add Template-Only Nodes

Control whether new keys from the template are added:

```ruby
# Add new keys from template
merger = Psych::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: true
)

# Skip template-only keys (default)
merger = Psych::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: false
)
```

### Freeze Blocks

Protect sections of your destination file from being overwritten:

```yaml
# destination.yml
database:
  host: localhost

# psych-merge:freeze
secrets:
  api_key: "super-secret-key-12345"
  password: "never-overwrite-this"
# psych-merge:unfreeze

cache:
  enabled: true
```

The content between `# psych-merge:freeze` and `# psych-merge:unfreeze` will be preserved from the destination, regardless of what the template contains.

#### Custom Freeze Token

Use a different marker for freeze blocks:

```ruby
merger = Psych::Merge::SmartMerger.new(
  template,
  destination,
  freeze_token: "my-app"  # Uses # my-app:freeze / # my-app:unfreeze
)
```

### Working with Anchors and Aliases

Psych::Merge properly handles YAML anchors and aliases:

```yaml
# template.yml
defaults: &defaults
  adapter: postgres
  host: localhost

development:
  <<: *defaults
  database: dev_db

production:
  <<: *defaults
  database: prod_db
```

### Debug Output

Get detailed information about the merge:

```ruby
merger = Psych::Merge::SmartMerger.new(template, destination)
debug_result = merger.merge_with_debug

puts debug_result[:content]      # The merged YAML
puts debug_result[:statistics]   # Stats about decisions made
puts debug_result[:decisions]    # Summary of merge decisions
```

Enable debug logging:

```bash
PSYCH_MERGE_DEBUG=1 ruby your_script.rb
```

### Custom Signature Generator

Customize how nodes are matched between files:

```ruby
custom_generator = ->(node) {
  if node.is_a?(Psych::Merge::MappingEntry) && node.key_name == "version"
    # Special handling for version keys
    [:version_key, node.key_name]
  else
    # Fall through to default signature computation
    node
  end
}

merger = Psych::Merge::SmartMerger.new(
  template,
  destination,
  signature_generator: custom_generator
)
```

### Error Handling

```ruby
begin
  merger = Psych::Merge::SmartMerger.new(template, destination)
  result = merger.merge
rescue Psych::Merge::TemplateParseError => e
  puts "Template has syntax errors: #{e.message}"
  e.errors.each { |err| puts "  #{err}" }
rescue Psych::Merge::DestinationParseError => e
  puts "Destination has syntax errors: #{e.message}"
  e.errors.each { |err| puts "  #{err}" }
end
```

## Architecture

Psych::Merge is composed of several components:

- **SmartMerger**: Main entry point orchestrating the merge process
- **FileAnalysis**: Analyzes YAML structure, extracts nodes and freeze blocks
- **ConflictResolver**: Resolves differences between template and destination
- **MergeResult**: Tracks merged content and decisions
- **CommentTracker**: Extracts and tracks comments with line numbers
- **NodeWrapper**: Wraps Psych::Nodes with comment associations
- **FreezeNode**: Represents freeze-protected sections
- **Emitter**: Custom YAML emitter preserving comments and formatting

## Related Projects

- [prism-merge](https://github.com/kettle-rb/prism-merge) - Intelligent Ruby file merging using Prism AST

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

```bash
bundle install
bundle exec rake spec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kettle-rb/psych-merge. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/kettle-rb/psych-merge/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Psych::Merge project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/kettle-rb/psych-merge/blob/main/CODE_OF_CONDUCT.md).
