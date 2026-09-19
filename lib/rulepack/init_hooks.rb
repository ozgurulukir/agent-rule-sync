# frozen_string_literal: true

require 'fileutils'
require_relative 'encoding_defaults'
require_relative 'common'

module Rulepack
  # InitHooks — the `rulepack init-hooks` backend: installs the pre-commit
  # audit hook into <root>/.git/hooks. The root resolves through the scoped
  # Paths (identical to RULEPACK_ROOT in production, sandbox-safe in tests).
  module InitHooks
    module_function

    def run(options = {}, paths: nil, ui: nil)
      if ui
        Rulepack::Common.with_ui(ui) { run(options, paths: paths) }
      elsif paths
        Rulepack::Common.with_paths(paths) { run_unscoped(options) }
      else
        run_unscoped(options)
      end
    end

    def run_unscoped(_options = {})
      root = Rulepack::Common.paths.root
      hook_dir = root.join('.git', 'hooks')
      unless hook_dir.exist?
        return Rulepack::Result.new(
          status: :failure,
          messages: ['❌ Error: Not a git repository (.git/hooks directory not found).']
        )
      end

      pre_commit_hook = hook_dir.join('pre-commit')
      File.write(pre_commit_hook, hook_content)
      File.chmod(0o755, pre_commit_hook)
      Rulepack::Result.new(
        status: :success,
        data: { hook_path: pre_commit_hook },
        messages: ["✅ Git pre-commit hook installed successfully at #{pre_commit_hook.relative_path_from(root)}"]
      )
    end

    def hook_content
      <<~HOOK.gsub('__RULEPACK_HOOK_EXIT__', 'exit')
        #!/bin/sh
        # Rulepack git pre-commit hook
        # Automatically runs PKGBUILD audit and drift verification before commits

        echo "🔍 Rulepack Pre-Commit Audit..."
        ruby bin/rulepack audit --strict
        AUDIT_STATUS=$?
        if [ $AUDIT_STATUS -ne 0 ]; then
          echo "❌ Rulepack pre-commit audit failed! Commit aborted."
          __RULEPACK_HOOK_EXIT__ 1
        fi

        echo "✓ Rulepack pre-commit audit passed."
        __RULEPACK_HOOK_EXIT__ 0
      HOOK
    end
  end
end
