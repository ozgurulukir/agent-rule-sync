# frozen_string_literal: true

# Test helper — sets up load paths and shared utilities

$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib')
$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib', 'rulepack')

require 'rulepack/encoding_defaults'

require 'minitest/autorun'
require 'pathname'
require 'tmpdir'
require 'fileutils'

ROOT = Pathname.new(__dir__).parent.expand_path

# Platform Registry Memoization Contract:
# ========================================
# The platform registry is cached after first load via Rulepack::Common.load_platform_registry
# (see lib/rulepack/platform.rb:54-67). Tests that modify data/registry/platforms.yaml or
# data/platforms/*.yaml MUST call Rulepack::Common.clear_platform_registry_cache! in their
# setup/teardown to ensure changes are picked up. Otherwise, the cached registry will cause
# false test passes or stale configuration bugs.
#
# Example:
#   def setup
#     Rulepack::Common.clear_platform_registry_cache!
#     # ... modify platform YAML ...
#   end
#
FIXTURES_ROOT = ROOT.join('test', 'fixtures')

# Load Rulepack modules
require 'rulepack/common'

module TestHelpers
  # Create a temporary directory and yield its Pathname
  def with_tmpdir
    Dir.mktmpdir do |tmpdir|
      yield Pathname.new(tmpdir)
    end
  end

  # Write a fixture file and return its Pathname
  def write_fixture(relative_path, content)
    path = FIXTURES_ROOT.join(relative_path)
    path.parent.mkpath
    path.write(content)
    path
  end

  # Clean up a fixture file
  def cleanup_fixture(relative_path)
    path = FIXTURES_ROOT.join(relative_path)
    path.delete if path.exist?
  end

  # Setup 5 local mock git repositories and rewrite target PKGBUILDs in packages_dir to point to them
  def mock_git_packages(packages_dir, mock_repos_dir)
    packages_dir = Pathname.new(packages_dir)
    mock_repos_dir = Pathname.new(mock_repos_dir)
    mock_repos_dir.mkpath

    git_packages = {
      'antigravity-skills' => {
        url: 'https://github.com/rmyndharis/antigravity-skills.git',
        setup_files: lambda { |dir|
          skills_dir = dir.join('skills')
          skills_dir.mkpath
          skills_dir.join('SKILL.md').write("# Root Skill\n")
          skill_a = skills_dir.join('skill_a')
          skill_a.mkpath
          skill_a.join('SKILL.md').write("# Skill A\n")
        }
      },
      'cc-skills-golang' => {
        url: 'https://github.com/samber/cc-skills-golang.git',
        setup_files: lambda { |dir|
          skills_dir = dir.join('skills')
          skills_dir.mkpath
          skills_dir.join('SKILL.md').write("# Go Skills\n")
          go_sec = skills_dir.join('go-security')
          go_sec.mkpath
          go_sec.join('SKILL.md').write("# Go Security\n")
        }
      },
      'ruby-agent-skills' => {
        url: 'https://github.com/DmitryPogrebnoy/ruby-agent-skills.git',
        setup_files: lambda { |dir|
          skills_dir = dir.join('plugins', 'ruby-type-signature-skills', 'skills')
          skills_dir.mkpath
          skills_dir.join('SKILL.md').write("# Ruby Skills\n")
          ruby_inline = skills_dir.join('ruby-inline')
          ruby_inline.mkpath
          ruby_inline.join('SKILL.md').write("# Ruby Inline\n")
        }
      },
      'ruby-update-signatures' => {
        url: 'https://github.com/DmitryPogrebnoy/ruby-agent-skills.git',
        setup_files: lambda { |dir|
          agents_dir = dir.join('plugins', 'ruby-type-signature-skills', 'agents')
          agents_dir.mkpath
          ruby_updater = agents_dir.join('ruby-updater')
          ruby_updater.mkpath
          ruby_updater.join('SKILL.md').write("---\ntitle: Ruby Updater\n---\n# Ruby Updater\n")
        }
      },
      'vibe-security' => {
        url: 'https://github.com/raroque/vibe-security-skill.git',
        setup_files: lambda { |dir|
          vibe_dir = dir.join('vibe-security')
          vibe_dir.mkpath
          vibe_dir.join('SKILL.md').write("# Vibe Security Skill\n")
        }
      },
      'anthropics-skills' => {
        url: 'https://github.com/anthropics/skills.git',
        setup_files: lambda { |dir|
          skills_dir = dir.join('skills')
          skills_dir.mkpath
          skills_dir.join('SKILL.md').write("# Anthropic Skills\n")
          mcp_dir = skills_dir.join('mcp-builder')
          mcp_dir.mkpath
          mcp_dir.join('SKILL.md').write("# MCP Builder Skill\n")
        }
      }
    }

    git_packages.each do |pkgname, cfg|
      pkg_repo = mock_repos_dir.join(pkgname)
      pkg_repo.mkpath

      # Create expected structure and files
      cfg[:setup_files].call(pkg_repo)

      # Initialize Git repository
      Dir.chdir(pkg_repo.to_s) do
        system('git', 'init', '--initial-branch=main', '--quiet') || system('git', 'init', '--quiet')
        system('git', 'config', 'user.name', 'Test')
        system('git', 'config', 'user.email', 'test@test.com')
        system('git', 'add', '.')
        system('git', 'commit', '-m', 'initial commit', '--quiet')
      end

      # Rewrite PKGBUILD URL using safe string replacement.
      # Git packages may live in the upstream namespace or the flat layout.
      pkgbuild_path = packages_dir.join('upstream', pkgname, 'PKGBUILD')
      pkgbuild_path = packages_dir.join(pkgname, 'PKGBUILD') unless pkgbuild_path.exist?

      if pkgbuild_path.exist?
        content = pkgbuild_path.read
        content.gsub!(cfg[:url], "file://#{pkg_repo.expand_path}")
        pkgbuild_path.write(content)
      end
    end
  end
end

# Set environment flag to disable interactive CLI TUI prompts during testing
ENV['RULEPACK_TEST'] = '1'

Minitest::Test.include TestHelpers
