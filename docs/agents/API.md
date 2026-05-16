# Rulepack API Documentation

Developer reference for extending and integrating with Rulepack.

## Table of Contents

- [Library Modules](#library-modules)
- [Common Module](#common-module)
- [Build API](#build-api)
- [Install API](#install-api)
- [Query API](#query-api)
- [Cache API](#cache-api)
- [Transformers API](#transformers-api)
- [Translators API](#translators-api)
- [Platform Registry](#platform-registry)
- [Version Comparison](#version-comparison)

---

## Library Modules

Rulepack is organized into modular components under `lib/rulepack/`:

| Module | Purpose | Key Classes/Functions |
|--------|---------|----------------------|
| `common.rb` | Shared utilities, config, constants | `Rulepack::Common`, `Rulepack::Config` |
| `logging.rb` | Centralized logging | `Rulepack::Common.log`, `log_error`, `log_warn` |
| `cache.rb` | HTTP/Git caching | `Rulepack::Common.cache_fetch`, `cache_store` |
| `backup.rb` | Backup/rollback support | `backup_index`, `restore_index` |
| `version.rb` | Version comparison | `Rulepack::Common.compare_versions` |
| `source.rb` | Source fetching | `fetch_git_source`, `fetch_url_source` |
| `transform.rb` | Content transformation | `apply_transformer`, `load_transformer` |
| `validation.rb` | PKGBUILD validation | `validate_pkgbuild`, `validate_target` |
| `platform.rb` | Platform registry | `load_platform_registry`, `platform_cfg_for` |
| `installer.rb` | Installation engine | `Rulepack::Install`, `install_package` |
| `uninstaller.rb` | Uninstallation logic | `uninstall_package_from_platform` |
| `build.rb` | Build orchestrator | Main build loop, per-package processing |
| `aggregate.rb` | Vendor skill aggregation | `aggregate_skills` |
| `query.rb` | Package database queries | `list_packages`, `show_package`, `search_packages` |
| `verify.rb` | Installation verification | `verify_platform`, `detect_drift` |
| `fix.rb` | Drift repair | `fix_platform`, `repair_drift` |

---

## Common Module

`lib/rulepack/common.rb` — Shared utilities used across all modules.

### Constants

```ruby
module Rulepack
  module Common
    RULEPACK_ROOT = Pathname.new(__dir__).parent.expand_path  # Project root
    BUILD_DIR = RULEPACK_ROOT.join('build')                     # Build artifacts
    BUILD_INDEX_PATH = BUILD_DIR.join('index.yaml')             # Build index
    CACHE_DIR = BUILD_DIR.join(Config.cache_dir_name)           # Cache directory
    LOG_PATH = BUILD_DIR.join('build.log')                      # Default log file
    INDEX_PATH = RULEPACK_ROOT.join('data', 'index.yaml')       # Master index
    REGISTRY_PATH = RULEPACK_ROOT.join('data', 'registry', 'platforms.yaml')
  end
end
```

### Configuration

```ruby
module Rulepack
  module Config
    module_function

    # Maximum HTTP redirects for URL fetches
    def max_redirects
      Integer(ENV.fetch('RULEPACK_MAX_REDIRECTS', '3'))
    end

    # HTTP read timeout in seconds
    def read_timeout
      Integer(ENV.fetch('RULEPACK_READ_TIMEOUT', '30'))
    end

    # Cache directory name under build/
    def cache_dir_name
      ENV.fetch('RULEPACK_CACHE_DIR', 'cache')
    end

    # Git shallow clone depth
    def git_clone_depth
      Integer(ENV.fetch('RULEPACK_GIT_DEPTH', '1'))
    end

    # Log level (:error, :warn, :info, :debug)
    def log_level
      ENV.fetch('RULEPACK_LOG_LEVEL', 'info').to_sym
    end
  end
end
```

### Logging

```ruby
# Set log file for current operation
Rulepack::Common.log_file = BUILD_DIR.join('install.log')

# Log at different levels
Rulepack::Common.log("Processing #{pkgname}...", level: :info)
Rulepack::Common.log_error("Failed to fetch #{url}: #{e.message}")
Rulepack::Common.log_warn("Cache miss for #{key}")
Rulepack::Common.log_debug("Checksum: #{checksum}")

# Timing helper
Rulepack::Common.time("fetch #{pkgname}") do
  # ... operation ...
end
```

### YAML/JSON I/O

```ruby
# Load YAML with safe_load
data = Rulepack::Common.load_yaml(path)

# Write YAML atomically (temp file + rename)
Rulepack::Common.write_yaml_atomic(path, data)

# Load JSON
data = Rulepack::Common.load_json(path)
```

### File Utilities

```ruby
# Validate output filename (no directory separators, no ..)
Rulepack::Common.validate_output_filename!("00-memory.md", :memory)
# => raises Rulepack::Error if invalid

# Validate target directory
Rulepack::Common.validate_target_dir!(".cursor/rules/", :cursor)

# Expand ~ in paths
expanded = Rulepack::Common.expand_user_path("~/.config/opencode/")
```

### Checksum Utilities

```ruby
# Compute SHA256 of file
checksum = Rulepack::Common.checksum_file(path)

# Compute SHA256 of string
checksum = Rulepack::Common.checksum_content(content)

# Verify checksum matches expected
Rulepack::Common.verify_checksum!(path, expected_sha256)
```

---

## Build API

`lib/rulepack/build.rb` — Main build orchestrator.

### Entry Point

```ruby
# Load and run build
load File.join(RULEPACK_ROOT, 'lib', 'rulepack', 'build.rb')
```

### Build Flow

1. **Discover PKGBUILDs**: `Dir.glob('data/packages/*/PKGBUILD')`
2. **Load registry**: `Rulepack::Common.load_platform_registry`
3. **Process each package**:
   - `load_pkgbuild(pkgbuild_path)` → parse YAML
   - `validate_pkgbuild(pkgbuild)` → schema check
   - `process_package(pkgbuild)` → fetch + transform + write
4. **Write build index**: `write_yaml_atomic(BUILD_INDEX_PATH, build_index_data)`
5. **Generate catalog**: `load generate-catalog.rb`

### Per-Package Processing

```ruby
def process_package(pkgbuild)
  pkgname = pkgbuild[:pkgname]
  
  # Fetch sources
  sources = fetch_sources(pkgbuild[:source], pkgname)
  
  # For each target
  pkgbuild[:targets].each do |target|
    # Fetch source content
    source_entry = sources.find { |s| s[:path] == target[:source] }
    content = File.read(source_entry[:local_path])
    
    # Translate (if specified)
    content = translate_content(content, target[:translate], pkgname: pkgname)
    
    # Transform
    content = Rulepack::Common.apply_transformer(
      target[:transformer],
      content,
      pkgname: pkgname
    )
    
    # Write artifact
    output_path = BUILD_DIR.join(target[:platform], target[:output])
    File.write(output_path, content)
    
    # Record checksum
    build_index[:packages][pkgname][:built][target[:platform]] = 
      Rulepack::Common.checksum_file(output_path)
  end
end
```

### Source Fetching

```ruby
# Local source
def fetch_local_source(entry, pkgname)
  path = RULEPACK_ROOT.join(entry[:path])
  { local_path: path, checksum: Rulepack::Common.checksum_file(path) }
end

# Git source
def fetch_git_source(entry, pkgname)
  url = entry[:url]
  ref = entry[:ref] || 'main'
  path_in_repo = entry[:path] || '.'
  
  # Clone to cache
  cache_key = "git-#{Digest::SHA256.hexdigest(url)}-#{ref}"
  repo_dir = CACHE_DIR.join(cache_key, 'repo')
  
  unless repo_dir.exist?
    clone_git_repo(url, repo_dir, ref: ref, depth: Config.git_clone_depth)
  end
  
  # Extract files
  source_dir = repo_dir.join(path_in_repo)
  # ... copy files to build directory ...
end

# URL source
def fetch_url_source(entry, pkgname)
  url = entry[:url]
  expected_sha256 = entry[:sha256]
  
  # Check cache first
  cache_key = "url-#{Digest::SHA256.hexdigest(url)}"
  cached = CACHE_DIR.join(cache_key, 'content')
  
  if cached.exist?
    content = File.read(cached)
    return content if Rulepack::Common.checksum_content(content) == expected_sha256
  end
  
  # Fetch
  content = Rulepack::Common.cached_fetch_url(url, max_redirects: Config.max_redirects)
  
  # Verify
  actual_sha256 = Rulepack::Common.checksum_content(content)
  unless actual_sha256 == expected_sha256
    raise Rulepack::Error, "SHA256 mismatch for #{url}: expected #{expected_sha256}, got #{actual_sha256}"
  end
  
  # Cache
  File.write(cached, content)
  content
end
```

---

## Install API

`lib/rulepack/installer.rb` — Installation engine.

### Entry Point

```ruby
module Rulepack
  module Install
    def self.run(argv)
      # Parse options
      options = parse_options(argv)
      
      # Load index
      index = Rulepack::Common.load_index
      
      # Load platform registry
      platforms = Rulepack::Common.load_platform_registry
      
      # Install
      platforms.each do |platform_id, platform_cfg|
        install_platform(platform_id, platform_cfg, index, options)
      end
      
      # Write index atomically
      Rulepack::Common.write_yaml_atomic(RULEPACK_ROOT.join('data', 'index.yaml'), index)
    end
  end
end
```

### Platform Installation

```ruby
def install_platform(platform_id, platform_cfg, index, options)
  # Resolve project root (for project-level platforms)
  project_root = if platform_cfg[:scope] == 'project'
    resolve_project_root(platform_cfg, options[:project])
  end
  
  # Get packages for this platform
  packages = index[:packages].select { |_, pkg| 
    pkg[:available_targets]&.include?(platform_id)
  }
  
  packages.each do |pkgname, pkg|
    # Find target for this platform
    target = pkg[:targets].find { |t| t[:platform] == platform_id }
    next unless target
    
    # Resolve install path
    install_path = resolve_install_path(platform_id, platform_cfg, target, project_root)
    
    # Perform install
    case target[:install][:type]
    when :symlink
      create_symlink(build_artifact_path, install_path)
    when :copy
      copy_file(build_artifact_path, install_path)
    when :inject
      inject_import_line(install_path, build_artifact_path, target[:install][:directive])
    when :append
      append_content(install_path, build_artifact_path)
    end
    
    # Record installation
    record_installation!(index, pkgname, platform_id, target, install_path)
  end
  
  # Skill platforms: run aggregation + copy vendor file
  if platform_cfg[:type] == 'skill'
    aggregate_skills(platform_id, index)
    copy_vendor_file(platform_id, platform_cfg, project_root)
  end
end
```

### Transaction Support

```ruby
def install_with_transaction(index, &block)
  backup_path = backup_index(index)  # Copy index to temp file
  
  begin
    block.call  # Perform installs
    
    # Write final index
    Rulepack::Common.write_yaml_atomic(INDEX_PATH, index)
    cleanup_backups(backup_path)
  rescue => e
    restore_index(backup_path)  # Restore pre-transaction state
    raise e
  end
end
```

---

## Query API

`lib/rulepack/query.rb` — Package database queries.

### Commands

```ruby
module Rulepack
  module Query
    def self.run(argv)
      command = argv.shift
      
      case command
      when 'list-packages'
        list_packages
      when 'show'
        show_package(argv.first)
      when 'search'
        search_packages(argv.first)
      when 'installed'
        list_installed(argv)
      when 'list-platforms'
        list_platforms
      end
    end
  end
end
```

### Listing Packages

```ruby
def list_packages
  index = Rulepack::Common.load_index
  index[:packages].each do |pkgname, pkg|
    puts "#{pkgname} (#{pkg[:pkgver]}) — #{pkg[:pkgdesc]}"
  end
end
```

### Showing Package Details

```ruby
def show_package(pkgname)
  index = Rulepack::Common.load_index
  pkg = index[:packages][pkgname.to_sym]
  
  puts "Package: #{pkg[:pkgname]}"
  puts "Version: #{Rulepack::Common.format_version(pkg)}"
  puts "Description: #{pkg[:pkgdesc]}"
  puts "Targets: #{pkg[:targets].map { |t| t[:platform] }.join(', ')}"
  puts "Installed: #{pkg[:installed].map { |i| "#{i[:platform]} (#{i[:output]})" }.join(', ')}"
end
```

### Searching

```ruby
def search_packages(query)
  index = Rulepack::Common.load_index
  results = index[:packages].select { |_, pkg|
    pkg[:tags]&.include?(query) ||
    pkg[:pkgdesc]&.downcase&.include?(query.downcase)
  }
  
  results.each { |pkgname, pkg| puts "#{pkgname}: #{pkg[:pkgdesc]}" }
end
```

---

## Cache API

`lib/rulepack/cache.rb` — HTTP/Git caching.

### HTTP Fetch with Caching

```ruby
def cached_fetch_url(url, max_redirects: Rulepack::Config.max_redirects)
  cache_key = "url-#{Digest::SHA256.hexdigest(url)}"
  cache_entry = CACHE_DIR.join(cache_key)
  
  # Check cache
  if cache_entry.exist?
    metadata = Rulepack::Common.load_json(cache_entry.join('metadata.json'))
    if metadata['expires_at'].nil? || Time.now < Time.parse(metadata['expires_at'])
      return File.read(cache_entry.join('content'))
    end
  end
  
  # Fetch
  response = fetch_with_redirects(url, max_redirects: max_redirects)
  content = response.body
  
  # Cache
  cache_entry.mkpath
  File.write(cache_entry.join('content'), content)
  
  metadata = {
    'url' => url,
    'fetched_at' => Time.now.utc.iso8601,
    'expires_at' => (Time.now + 86400).utc.iso8601,  # 24 hours
    'sha256' => Rulepack::Common.checksum_content(content)
  }
  File.write(cache_entry.join('metadata.json'), JSON.pretty_generate(metadata))
  
  content
end
```

### Git Clone Caching

```ruby
def cached_git_clone(url, ref, cache_key)
  repo_dir = CACHE_DIR.join(cache_key, 'repo')
  
  return repo_dir if repo_dir.exist?  # Cache hit
  
  # Clone
  repo_dir.mkpath
  system('git', 'clone', '--depth', Config.git_clone_depth.to_s, '--branch', ref, url, repo_dir.to_s)
  
  repo_dir
end
```

---

## Transformers API

`lib/rulepack/transform.rb` — Content transformation.

### Loading Transformers

```ruby
def load_transformer(spec)
  case spec
  when 'copy'
    ->(content, **opts) { content }
  when 'strip-frontmatter'
    ->(content, **opts) { strip_frontmatter(content) }
  when /^custom:(.+)$/
    path = $1
    require_relative File.join(RULEPACK_ROOT, path)
    Transform.new(content: '', pkgname: nil).method(:transform)
  else
    raise Rulepack::Error, "Unknown transformer: #{spec}"
  end
end
```

### Built-in Transformers

```ruby
def strip_frontmatter(content)
  if content.start_with?('---')
    lines = content.lines
    end_idx = lines.index { |l| l.strip == '---' } || 0
    lines[(end_idx + 1)..-1].join
  else
    content
  end
end
```

### Custom Transformer Interface

```ruby
# data/transformers/example.rb
class Transform
  def initialize(content:, pkgname:)
    @content = content
    @pkgname = pkgname
  end

  def transform
    # Transform @content and return new string
    @content
  end
end
```

---

## Translators API

`lib/rulepack/translate.rb` — Content translation.

### Loading Translators

```ruby
def load_translator(spec)
  case spec
  when 'copy', nil
    ->(content, **opts) { content }
  when /^custom:(.+)$/
    path = $1
    require_relative File.join(RULEPACK_ROOT, path)
    Translator.method(:translate)
  else
    raise Rulepack::Error, "Unknown translator: #{spec}"
  end
end
```

### Custom Translator Interface

```ruby
# data/translators/example.rb
class Translator
  def self.translate(content, args: {})
    pkgname = args[:pkgname]
    # Transform content
    content
  end
end
```

---

## Platform Registry

`data/registry/platforms.yaml` — Platform definitions.

### Loading Registry

```ruby
def load_platform_registry
  @platform_registry ||= begin
    raw = Rulepack::Common.load_yaml(Rulepack::Common::REGISTRY_PATH)
    raw.each { |id, cfg| validate_platform_config(id, cfg) }
    raw
  end
end

def clear_platform_registry_cache!
  @platform_registry = nil
end
```

### Platform Config Structure

```ruby
{
  "opencode" => {
    "type" => "directory",
    "scope" => "user",
    "display_name" => "OpenCode",
    "base_path" => "~/.config/opencode/",
    "rules_dir" => "rules/",
    "skills_dir" => "skills/",
    "rule_install" => { "type" => "symlink" },
    "skill_install" => { "type" => "copy" },
    "prerequisites" => { "tools" => ["ruby"] }
  }
}
```

### Resolving Install Paths

```ruby
def resolve_install_path(platform_id, platform_cfg, target, project_root)
  base = if platform_cfg[:scope] == 'user'
    File.expand_path(platform_cfg[:base_path])
  else
    project_root.join(platform_cfg[:base_path])
  end
  
  case platform_cfg[:type]
  when 'directory'
    if target[:format] == 'skill'
      base.join(platform_cfg[:skills_dir], target[:output])
    else
      base.join(platform_cfg[:rules_dir], target[:output])
    end
  when 'skill'
    base.join(platform_cfg[:skill_file])
  when 'import'
    base.join(platform_cfg[:config_file])
  end
end
```

---

## Version Comparison

`lib/rulepack/version.rb` — Pacman-style version comparison.

### API

```ruby
# Compare two version strings
# Returns: 1 if a > b, -1 if a < b, 0 if equal
result = Rulepack::Common.compare_versions('1:2.0-1', '1:1.9-1')
# => 1

# Format version components to string
version_str = Rulepack::Common.format_version(
  epoch: 0,
  pkgver: '1.0.0',
  pkgrel: 1
)
# => '1.0.0-1'
```

### Comparison Algorithm

```ruby
def compare_versions(a, b)
  a_parts = parse_version(a)
  b_parts = parse_version(b)
  
  # Compare epoch
  cmp = a_parts[:epoch] <=> b_parts[:epoch]
  return cmp unless cmp == 0
  
  # Compare pkgver (segment-by-segment)
  cmp = compare_pkgver(a_parts[:pkgver], b_parts[:pkgver])
  return cmp unless cmp == 0
  
  # Compare pkgrel
  a_parts[:pkgrel] <=> b_parts[:pkgrel]
end
```

---

## Error Handling

All errors inherit from `Rulepack::Error`:

```ruby
module Rulepack
  class Error < StandardError; end
  class BuildError < Error; end
  class InstallError < Error; end
  class ValidationError < Error; end
  class ChecksumError < Error; end
  class PathTraversalError < Error; end
end
```

### Raising Errors

```ruby
raise Rulepack::Error, "Build index not found at #{path}. Run `bin/rulepack build` first."
raise Rulepack::ChecksumError, "SHA256 mismatch for #{url}: expected #{expected}, got #{actual}."
raise Rulepack::PathTraversalError, "Path traversal not allowed: #{path}"
```

---

## Testing

### Running Tests

```bash
rake test                    # All tests
rake test_unit               # Unit tests only
rake test_integration        # Integration tests
rake test_cache              # Cache tests
rake test_pkgbuild           # PKGBUILD validation
rake test_platform           # Platform registry tests
```

### Test Structure

```ruby
# test/test_common.rb
class TestCompareVersions < Minitest::Test
  def test_equal_versions
    assert_equal 0, Rulepack::Common.compare_versions('1.0.0', '1.0.0')
  end
  
  def test_newer_version
    assert_equal 1, Rulepack::Common.compare_versions('1.1.0', '1.0.0')
  end
end
```

### Test Helpers

```ruby
# test/helper.rb
module TestHelpers
  def with_tmpdir
    Dir.mktmpdir do |tmpdir|
      yield Pathname.new(tmpdir)
    end
  end
  
  def with_isolated_registry
    old_registry = Rulepack::Common.instance_variable_get(:@platform_registry)
    Rulepack::Common.clear_platform_registry_cache!
    yield
  ensure
    Rulepack::Common.instance_variable_set(:@platform_registry, old_registry)
  end
end
```

---

## Extension Points

### Adding a New Transformer

1. Create `data/transformers/my-transform.rb`
2. Define `Transform` class with `#transform` method
3. Reference in PKGBUILD: `transformer: custom:transformers/my-transform.rb`

### Adding a New Translator

1. Create `data/translators/my-translate.rb`
2. Define `Translator` class with `.translate` class method
3. Reference in PKGBUILD: `translate: custom:translators/my-translate.rb`

### Adding a New Platform

1. Add to `data/registry/platforms.yaml`
2. Add platform-specific logic in `lib/rulepack/install.rb` if needed
3. Create platform format profile in `data/platforms/<agent>.yaml`
4. Add agent guide in `docs/agents/agents/<agent>.md`

---

## See Also

- [Architecture](ARCHITECTURE.md) — System design
- [Reference](REFERENCE.md) — PKGBUILD schema, index format
- [Usage](USAGE.md) — User guide
- [Transforms](TRANSFORMS.md) — Transformer/translator docs
