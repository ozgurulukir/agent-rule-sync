# Frequently Asked Questions

## General

### What is Rulepack?

Rulepack is a PKGBUILD-inspired package manager for AI coding agent rules and skills. It provides a single authoritative source for rules that can be deployed to multiple agent platforms (OpenCode, Cursor, Claude Code, etc.) with per-platform format transformation.

### How is Rulepack different from other rule managers?

Rulepack uses a package-based architecture where each rule is a package with a declarative PKGBUILD descriptor. This allows:
- **Single source, multiple targets**: Write once, deploy to 14+ platforms
- **Change detection**: SHA256 checksums track installed state
- **Atomic installs**: Rollback capability on failure
- **Platform-specific transformation**: Each target can apply custom transformers

### Which platforms are supported?

See [Platforms](agents/PLATFORMS.md) for the full list of 14 supported platforms, including OpenCode, Cursor, Claude Code, GitHub Copilot, Windsurf, and more.

---

## Installation & Setup

### How do I install Rulepack?

```bash
# Clone the repository
git clone <repo-url>
cd agent-rule-sync

# Build all packages
bin/rulepack build

# Install to a platform
bin/rulepack install opencode
```

### What are the prerequisites?

- **Ruby 2.7+** (for build system — stdlib only, no gems)
- **Git** (for fetching remote sources)

---

## Usage

### How do I build packages?

```bash
bin/rulepack build
```

This reads all `PKGBUILD` files from `data/packages/*/`, fetches sources, applies transformers, and writes artifacts to `build/<platform>/`.

### How do I install rules to a platform?

```bash
# User-level platform (global)
bin/rulepack install opencode

# Project-level platform (version-controlled)
bin/rulepack install cursor --project .

# Install specific package to a platform
bin/rulepack install memory --target opencode

# Install with pacman-style flag
bin/rulepack install -S opencode
```

### How do I check what's installed?

```bash
# Show package details
bin/rulepack show memory

# Search packages by tag
bin/rulepack search security

# Verify installed state matches index
bin/rulepack verify opencode

# Query package database
bin/rulepack query show memory
bin/rulepack query search shell
```

### How do I update rules?

```bash
# Rebuild and reinstall
bin/rulepack build
bin/rulepack install opencode

# Force reinstall (allows downgrades)
bin/rulepack install opencode --force
```

---

## Troubleshooting

### "No build index found"

**Problem**: `bin/rulepack install` fails with "No build index found"

**Solution**: Run `bin/rulepack build` first to generate the build index.

```bash
bin/rulepack build
bin/rulepack install opencode
```

### "Platform not found"

**Problem**: Install fails with "Platform not found: xyz"

**Solution**: Check available platforms:

```bash
bin/rulepack platforms
```

Ensure the platform ID matches exactly (e.g., `claude-code`, not `claude`).

### "Checksum mismatch"

**Problem**: Build fails with SHA256 mismatch for a URL source

**Solution**: The source file may have changed upstream. Update the `sha256` field in the PKGBUILD:

```bash
# Fetch and compute new checksum
curl -sL https://example.com/file.md | sha256sum
```

Then update `data/packages/<name>/PKGBUILD`.

### "Path traversal not allowed"

**Problem**: Build fails with path traversal error

**Solution**: Ensure all `source[].path` values are within the package directory. Don't use `../` to escape the package root.

### Platform not picking up changes

**Problem**: I updated a rule but the agent isn't seeing changes

**Solution**:
1. Verify the artifact was rebuilt: `ls build/<platform>/`
2. Reinstall: `bin/rulepack install opencode --force`
3. Check the agent's config location (some agents cache rules)
4. Repair drift: `bin/rulepack fix opencode`

---

## Development

### How do I add a new package?

See [Usage](agents/USAGE.md) for a step-by-step guide.

### How do I create a custom transformer?

Create a Ruby class in `data/transformers/`:

```ruby
# data/transformers/my-transform.rb
class Transform
  def initialize(content:, pkgname:)
    @content = content
    @pkgname = pkgname
  end

  def transform
    # Your transformation here
    @content.upcase
  end
end
```

Set the platform's `default_transformer` in `data/registry/platforms.yaml` for automatic resolution, or use it as an advanced override in PKGBUILD:

```yaml
targets:
  - platform: opencode
    transformer: custom:data/transformers/my-transform.rb
```

### How do I create a custom translator?

Similar to transformers, but in `data/translators/`:

```ruby
# data/translators/my-translate.rb
class Translator
  def self.translate(content, args: {})
    pkgname = args[:pkgname]
    # Your translation here
    content
  end
end
```

### How do I add a new platform?

1. Add platform definition to `data/registry/platforms.yaml`
2. Create platform format profile in `data/platforms/<agent>.yaml`
3. Create platform guide in `docs/agents/platforms/<agent>.md`

---

## Advanced

### How does the build index work?

The build index (`build/index.yaml`) tracks:
- Package checksums (source and built artifacts)
- Available targets per package
- Build metadata (timestamp, version)

It's separate from `data/index.yaml` (the master package database) to allow rebuilding without affecting installed state.

### What's the difference between `build/` and `data/`?

- **`data/`**: Source of truth — package definitions, registry, master index
- **`build/`**: Generated artifacts — built rules, intermediate index, cache

Never edit files in `build/` directly; they're overwritten on each build.

### How does aggregation work for skill agents?

For skill-based platforms (Crush, Goose, Droid, Codex), Rulepack aggregates multiple rule fragments into a single vendor skill file:

1. Collects all packages with `format: skill` targets
2. Orders them by `order` field
3. Adds agent-specific header
4. Appends common skills
5. Writes to `build/<agent>/skills/vendor/<agent>.md`

### How do I run tests?

```bash
rake test                    # All tests (277 tests, 855 assertions)
```

### How do I debug a build?

Enable debug logging:

```bash
RULEPACK_LOG_LEVEL=debug bin/rulepack build
```

---

## Platform-Specific

### Cursor: Rules not showing up

- Ensure rules are in `.cursor/rules/` directory
- Check that filenames end with `.md`
- Restart Cursor after installing rules

### Claude Code: Rules not loading

- Claude Code reads rules from `.claude/rules/` in the project
- Ensure you're running from the project root
- Install with: `bin/rulepack install claude-code --project .`

### GitHub Copilot: Instructions not applying

- Copilot reads `.github/copilot-instructions.md` in the repository root
- Ensure the file exists and is committed
- Instructions may take a minute to activate after changes

### OpenCode: Rules not loading

- OpenCode reads from `~/.config/opencode/rules/`
- Ensure files are symlinked correctly: `ls -la ~/.config/opencode/rules/`
- Restart OpenCode after installing rules
