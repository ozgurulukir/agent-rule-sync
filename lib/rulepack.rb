# frozen_string_literal: true

# Rulepack — declarative package manager for AI-agent rules and skills.
#
# LIBRARY entry point. Requiring it gives the full Rulepack API with NO CLI or
# process side effects (no `exit`, no ARGV parsing, no signal traps):
#
#   require 'rulepack'
#   result = Rulepack::Build.run(target: 'opencode')
#   result.success? # => true / false
#
# The CLI (bin/rulepack) requires this file and layers process concerns on top.
#
# NOTE: Command modules are required lazily by callers for now; Step 2 moves
# them here once their `exit` calls are removed. `errors` + `common` load
# eagerly so Rulepack::Error and the Common facade are always available.

require_relative 'rulepack/encoding_defaults'
require_relative 'rulepack/errors'
require_relative 'rulepack/emitter'
require_relative 'rulepack/models/package'
require_relative 'rulepack/models/platform'
require_relative 'rulepack/models/target'
require_relative 'rulepack/reporter/console_renderer'
require_relative 'rulepack/reporter/jsonl_renderer'
require_relative 'rulepack/catalog/source_repository'
require_relative 'rulepack/catalog/local_catalog'
require_relative 'rulepack/catalog/remote_catalog'
require_relative 'rulepack/lockfile'
require_relative 'rulepack/common'

module Rulepack
  # Stable library entry point for root queries.
  def self.root
    Rulepack::Common::RULEPACK_ROOT
  end
end
