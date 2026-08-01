# frozen_string_literal: true

require 'yaml'

# Lockfile — pins (pkgname, version, source_sha256) tuples for reproducible installs.
#
# Usage:
#   lock = Rulepack::Lockfile.new('rulepack.lock')
#   lock.add('memory', version: '1.0.0', source_sha256: 'abc...')
#   lock.write!
#   lock.locked?('memory', version: '1.0.0')  # => true
#
#   # Enforce during install:
#   lock.enforce!(pkgname, version: '1.0.0')
module Rulepack
  class Lockfile
    def initialize(path = nil)
      @path = path || Pathname.new(Dir.pwd).join('rulepack.lock')
      @entries = {}
      load! if @path.exist?
    end

    def add(pkgname, version:, source_sha256: nil, pkgrel: nil, epoch: nil)
      @entries[pkgname.to_s] = {
        'version' => version.to_s,
        'source_sha256' => source_sha256,
        'pkgrel' => pkgrel,
        'epoch' => epoch
      }.compact
    end

    def remove(pkgname)
      @entries.delete(pkgname.to_s)
    end

    def locked?(pkgname, version: nil, source_sha256: nil)
      entry = @entries[pkgname.to_s]
      return false unless entry

      return false if version && entry['version'] != version.to_s
      return false if source_sha256 && entry['source_sha256'] && entry['source_sha256'] != source_sha256

      true
    end

    def enforce!(pkgname, version:, source_sha256: nil)
      entry = @entries[pkgname.to_s]
      unless entry
        raise Rulepack::StateError, "Package '#{pkgname}' is not locked. Run `rulepack lock` first."
      end

      if version && entry['version'] != version.to_s
        raise Rulepack::StateError, "Version mismatch for '#{pkgname}': locked #{entry['version']}, requested #{version}"
      end

      if source_sha256 && entry['source_sha256'] && entry['source_sha256'] != source_sha256
        raise Rulepack::StateError, "Source hash mismatch for '#{pkgname}': locked #{entry['source_sha256']}, requested #{source_sha256}"
      end

      true
    end

    def entries
      @entries.dup
    end

    def write!
      @path.dirname.mkpath
      @path.write(YAML.dump({
        'version' => 1,
        'generated' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'packages' => @entries
      }))
    end

    private

    def load!
      data = YAML.safe_load(@path.read, permitted_classes: [Symbol])
      return unless data

      @entries = data['packages'] || data[:packages] || {}
    end
  end
end
