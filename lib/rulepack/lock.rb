# frozen_string_literal: true

require_relative 'encoding_defaults'
require_relative 'common'
require_relative 'lockfile'
require_relative 'build_index'

module Rulepack
  # Lock — the `rulepack lock` backend.
  #
  #   rulepack lock                  # read-only status report
  #   rulepack lock <pkg>...         # pin (pkgname, version, source_sha256)
  #                                  # from build/index.yaml and write the file
  #   rulepack lock --remove <pkg>.. # unpin
  #
  # The lockfile anchors to the working directory by design.
  module Lock
    module_function

    def run(options = {}, paths: nil, ui: nil, lockfile: nil)
      if ui
        Rulepack::Common.with_ui(ui) { run(options, paths: paths, lockfile: lockfile) }
      elsif paths
        Rulepack::Common.with_paths(paths) { run_unscoped(options, lockfile) }
      else
        run_unscoped(options, lockfile)
      end
    end

    def run_unscoped(options = {}, lockfile = nil)
      lockfile ||= Rulepack::Lockfile.new
      packages = Array(options[:positional]).map(&:to_s)
      return status_report(lockfile) if packages.empty?

      build_index = Rulepack::BuildIndex.load_or_nil
      unless build_index
        return Rulepack::Result.new(
          status: :failure,
          messages: ['❌ No build index found. Run `rulepack build` first.']
        )
      end

      remove_mode = options.fetch(:remove, false)
      entries_before = lockfile.entries
      changed = []
      missing = []
      packages.each do |pkgname|
        pkg = build_index[:packages][pkgname] || build_index[:packages][pkgname.to_sym]
        if pkg.nil?
          missing << pkgname
          next
        end
        if remove_mode
          lockfile.remove(pkgname)
          changed << "🔓 Unpinned #{pkgname}"
        else
          lockfile.add(pkgname, version: pkg[:pkgver], source_sha256: pkg[:source_sha256],
                               pkgrel: pkg[:pkgrel], epoch: pkg[:epoch])
          changed << "📌 Pinned #{pkgname} #{pkg[:pkgver]}"
        end
      end

      # Skip the write when the operation was a no-op (idempotent re-pin,
      # removing a package that was never pinned) — don't churn the stamp.
      lockfile.write! unless changed.empty? || lockfile.entries == entries_before

      changed.each { |line| Rulepack::Common.log line }
      missing.each do |pkgname|
        Rulepack::Common.log_error "Package '#{pkgname}' not found in build index."
      end

      Rulepack::Result.new(
        status: missing.empty? ? :success : :failure,
        view: :lock,
        data: { entries: lockfile.entries },
        messages: changed,
        errors: missing.map { |pkgname| "Package '#{pkgname}' not found in build index." }
      )
    rescue StandardError => e
      Rulepack::Result.new(status: :failure, messages: ["❌ Error: #{e.message}"])
    end

    def status_report(lockfile)
      Rulepack::Result.new(
        status: :success,
        view: :lock,
        data: { entries: lockfile.entries }
      )
    end
  end
end
