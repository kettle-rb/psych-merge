# AGENTS.md - psych-merge Development Guide

## 🎯 Project Overview

`psych-merge` is a **format-specific implementation of the `*-merge` gem family** for YAML files. It provides intelligent YAML file merging using AST analysis via Ruby's standard library Psych parser.

**Core Philosophy**: Intelligent YAML merging that preserves structure, comments, anchors, and formatting while applying updates from templates.

**Repository**: https://github.com/kettle-rb/psych-merge
**Current Version**: 1.0.0
**Required Ruby**: >= 3.2.0 (currently developed against Ruby 4.0.1)

## 🏗️ Architecture: Format-Specific Implementation

### What psych-merge Provides

- **`Psych::Merge::SmartMerger`** – YAML-specific SmartMerger implementation
- **`Psych::Merge::FileAnalysis`** – YAML file analysis with mapping/sequence extraction
- **`Psych::Merge::NodeWrapper`** – Wrapper for Psych AST nodes (mappings, sequences, scalars)
- **`Psych::Merge::MappingEntry`** – Key-value pair representation
- **`Psych::Merge::MergeResult`** – YAML-specific merge result
- **`Psych::Merge::ConflictResolver`** – YAML conflict resolution
- **`Psych::Merge::FreezeNode`** – YAML freeze block support
- **`Psych::Merge::DebugLogger`** – Psych-specific debug logging

### Key Dependencies

| Gem | Role |
|-----|------|
| `ast-merge` (~> 4.0) | Base classes and shared infrastructure |
| `tree_haver` (~> 5.0) | Unified parser adapter (wraps Psych) |
| `psych` (stdlib) | Ruby's built-in YAML parser |
| `version_gem` (~> 1.1) | Version management |

### Parser Backend

psych-merge uses Ruby's standard library `Psych` parser exclusively via TreeHaver's `:psych_backend`:

| Backend | Parser | Platform | Notes |
|---------|--------|----------|-------|
| `:psych_backend` | Psych (stdlib) | All Ruby platforms | Built into Ruby, no external dependencies |

## 📁 Project Structure

```
lib/psych/merge/
├── smart_merger.rb          # Main SmartMerger implementation
├── file_analysis.rb         # YAML file analysis (mappings, sequences)
├── node_wrapper.rb          # AST node wrapper for Psych nodes
├── mapping_entry.rb         # Key-value pair representation
├── merge_result.rb          # Merge result object
├── conflict_resolver.rb     # Conflict resolution
├── freeze_node.rb           # Freeze block support
├── debug_logger.rb          # Debug logging
└── version.rb

spec/psych/merge/
├── smart_merger_spec.rb
├── file_analysis_spec.rb
├── node_wrapper_spec.rb
├── mapping_entry_spec.rb
└── integration/
```

## 🔧 Development Workflows

### Running Tests

```bash
# Full suite (required for coverage thresholds)
bundle exec rspec

# Single file (disable coverage threshold check)
K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/psych/merge/smart_merger_spec.rb
```

**Note**: Always run commands in the project root (`/home/pboling/src/kettle-rb/ast-merge/vendor/psych-merge`). Allow `direnv` to load environment variables first by doing a plain `cd` before running commands.

### Coverage Reports

```bash
cd /home/pboling/src/kettle-rb/ast-merge/vendor/psych-merge
bin/rake coverage && bin/kettle-soup-cover -d
```

**Key ENV variables** (set in `.envrc`, loaded via `direnv allow`):
- `K_SOUP_COV_DO=true` – Enable coverage
- `K_SOUP_COV_MIN_LINE=100` – Line coverage threshold
- `K_SOUP_COV_MIN_BRANCH=82` – Branch coverage threshold
- `K_SOUP_COV_MIN_HARD=true` – Fail if thresholds not met

### Code Quality

```bash
bundle exec rake reek
bundle exec rake rubocop_gradual
```

## 📝 Project Conventions

### API Conventions

#### SmartMerger API
- `merge` – Returns a **String** (the merged YAML content)
- `merge_result` – Returns a **MergeResult** object
- `to_s` on MergeResult returns the merged content as a string

#### YAML-Specific Features

**Mapping Merging**:
```ruby
merger = Psych::Merge::SmartMerger.new(template_yaml, dest_yaml)
result = merger.merge
```

**Freeze Blocks**:
```yaml
database:
  # psych-merge:freeze
  password: custom_secret  # Don't override this
  # psych-merge:unfreeze
  host: localhost
```

**Anchor/Alias Support**:
```yaml
defaults: &defaults
  timeout: 30
  retries: 3

production:
  <<: *defaults
  host: prod.example.com
```

### kettle-dev Tooling

This project uses `kettle-dev` for gem maintenance automation:

- **Rakefile**: Sourced from kettle-dev template
- **CI Workflows**: GitHub Actions and GitLab CI managed via kettle-dev
- **Releases**: Use `kettle-release` for automated release process

### Version Requirements
- Ruby >= 3.2.0 (gemspec), developed against Ruby 4.0.1 (`.tool-versions`)
- `ast-merge` >= 4.0.0 required
- `tree_haver` >= 5.0.3 required
- `psych` (Ruby stdlib, always available)

## 🧪 Testing Patterns

### TreeHaver Dependency Tags

All spec files use TreeHaver RSpec dependency tags for conditional execution:

**Available tags**:
- `:psych_backend` – Requires Psych backend (always available in Ruby)
- `:yaml_parsing` – Requires YAML parser (always available)

✅ **CORRECT** – Use dependency tag on describe/context/it:
```ruby
RSpec.describe Psych::Merge::SmartMerger, :psych_backend do
  # Standard pattern even though Psych is always available
end

it "parses YAML", :yaml_parsing do
  # Consistent with other *-merge gems
end
```

❌ **WRONG** – Never use manual skip checks:
```ruby
before do
  skip "Requires Psych" unless defined?(Psych)  # DO NOT DO THIS
end
```

### Shared Examples

psych-merge uses shared examples from `ast-merge`:

```ruby
it_behaves_like "Ast::Merge::FileAnalyzable"
it_behaves_like "Ast::Merge::ConflictResolverBase"
it_behaves_like "a reproducible merge", "scenario_name", { preference: :template }
```

## 🔍 Critical Files

| File | Purpose |
|------|---------|
| `lib/psych/merge/smart_merger.rb` | Main YAML SmartMerger implementation |
| `lib/psych/merge/file_analysis.rb` | YAML file analysis and mapping extraction |
| `lib/psych/merge/node_wrapper.rb` | Psych node wrapper with YAML-specific methods |
| `lib/psych/merge/mapping_entry.rb` | Key-value pair abstraction |
| `lib/psych/merge/debug_logger.rb` | Psych-specific debug logging |
| `spec/spec_helper.rb` | Test suite entry point |
| `.envrc` | Coverage thresholds and environment configuration |

## 🚀 Common Tasks

```bash
# Run all specs with coverage
bundle exec rake spec

# Generate coverage report
bundle exec rake coverage

# Check code quality
bundle exec rake reek
bundle exec rake rubocop_gradual

# Prepare and release
kettle-changelog && kettle-release
```

## 🌊 Integration Points

- **`ast-merge`**: Inherits base classes (`SmartMergerBase`, `FileAnalyzable`, etc.)
- **`tree_haver`**: Wraps Psych parser in unified TreeHaver interface
- **`psych`**: Ruby's standard library YAML parser (libyaml binding)
- **RSpec**: Full integration via `ast/merge/rspec` and `tree_haver/rspec`
- **SimpleCov**: Coverage tracked for `lib/**/*.rb`; spec directory excluded

## 💡 Key Insights

1. **Psych is always available**: It's part of Ruby stdlib, but we still use TreeHaver for consistency
2. **MappingEntry abstraction**: YAML key-value pairs are wrapped for easier manipulation
3. **Anchor/alias preservation**: Psych AST includes anchors and aliases; we preserve them during merge
4. **Comment tracking**: Comments are associated with nodes via `CommentTracker`
5. **Freeze blocks use `# psych-merge:freeze`**: Language-specific comment syntax
6. **Document vs Stream**: Psych parses into Stream → Document → Node hierarchy; we handle all levels
7. **Scalar quoting**: Psych provides raw scalar values; quoting style is preserved in source

## 🚫 Common Pitfalls

1. **NEVER assume all YAML is valid**: Use `FileAnalysis#valid?` to check parse success
2. **NEVER use manual skip checks** – Use dependency tags (`:psych_backend`, `:yaml_parsing`)
3. **Do NOT forget nil checks**: YAML allows null values; handle them explicitly
4. **Do NOT load vendor gems** – They are not part of this project; they do not exist in CI
5. **Use `tmp/` for temporary files** – Never use `/tmp` or other system directories
6. **Do NOT chain `cd` with `&&`** – Run `cd` as a separate command so `direnv` loads ENV

## 🔧 YAML-Specific Notes

### Node Types in Psych
```ruby
Psych::Nodes::Stream     # Top-level container
Psych::Nodes::Document   # YAML document (can have multiple per stream)
Psych::Nodes::Mapping    # Key-value pairs (hashes)
Psych::Nodes::Sequence   # Arrays/lists
Psych::Nodes::Scalar     # Strings, numbers, booleans
Psych::Nodes::Alias      # Reference to an anchor
```

### Merge Behavior
- **Mappings**: Matched by key name; deeply nested mappings are traversed
- **Sequences**: Can be merged or replaced based on preference
- **Scalars**: Leaf values; matched by context (parent key)
- **Anchors**: Preserved; aliases remain valid after merge
- **Comments**: Preserved when attached to mappings/sequences
- **Freeze blocks**: Protect customizations from template updates

### MappingEntry Structure
```ruby
entry = Psych::Merge::MappingEntry.new(
  key: key_wrapper,      # NodeWrapper for key
  value: value_wrapper,  # NodeWrapper for value
  lines: lines,
  comment_tracker: tracker
)

entry.key_name         # String key name
entry.value_node       # Access wrapped value node
entry.start_line       # Line number in source
```
