# frozen_string_literal: true

# Immutable value object for an installed-record entry (one (package, platform,
# output) record inside data/index.yaml's packages.<name>.installed array).
#
# The schema lives here and only here: from_h constructs the record from the
# raw YAML hash (tolerant of missing/legacy fields), to_h serializes the exact
# key set install_execute.rb has always written. The on-disk format is
# unchanged — no migration; ownership is purely at the read/write boundary.
module Rulepack
  class InstalledRecord < Data.define(
    :platform, :version, :pkgrel, :epoch, :output, :checksum,
    :format, :target_path, :installed_at
  )
    # rubocop:disable Lint/StructNewOverride

    def self.from_h(hash)
      new(
        platform:     hash[:platform],
        version:      hash[:version],
        pkgrel:       hash[:pkgrel],
        epoch:        hash[:epoch],
        output:       hash[:output],
        checksum:     hash[:checksum],
        format:       hash[:format],
        target_path:  hash[:target_path],
        installed_at: hash[:installed_at]
      )
    end

    def to_h
      {
        platform: platform,
        version: version,
        pkgrel: pkgrel,
        epoch: epoch,
        output: output,
        checksum: checksum,
        format: format,
        target_path: target_path,
        installed_at: installed_at
      }
    end

    # The one canonical format rule. Legacy records may omit :format; the
    # build target is the next authority, and 'directory' is the historical
    # default (install_execute.rb's original derivation).
    def canonical_format(target_format = nil)
      format || target_format || 'directory'
    end
  end
end
