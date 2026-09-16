# frozen_string_literal: true

# Immutable value object for a build-index entry (one package's record in
# build/index.yaml).
#
# The schema lives here and only here: BuildRecord.from_package seeds the
# record from a Package, the build pipeline accumulates runtime fields via
# Data#with (source_dir / source_sha256 at fetch time; available_targets /
# checksums.built per target), and #to_h is the single serialization point
# to YAML. Install-side readers keep consuming the YAML hashes — but any
# key they rely on must appear in #to_h, enforced by the invariants below.
module Rulepack
  class BuildRecord < Data.define(
    :pkgver, :pkgrel, :epoch, :pkgdesc, :pkg_type, :order,
    :dependencies, :conflicts, :provides, :tags,
    :targets, :available_targets, :checksums,
    :source_dir, :source_sha256
  )
    # rubocop:disable Lint/StructNewOverride

    # Seed from a Package and open the runtime slots. checksums[:source] is
    # set alongside source_sha256 — aggregate/bump read the source checksum
    # for materializable packages from there.
    def self.from_package(package)
      record = new(
        pkgver: package.pkgver, pkgrel: package.pkgrel, epoch: package.epoch,
        pkgdesc: package.pkgdesc, pkg_type: package.pkg_type, order: package.order,
        dependencies: package.dependencies, conflicts: package.conflicts,
        provides: package.provides, tags: package.tags,
        targets: package.targets || [],
        available_targets: [],
        checksums: { source: nil, built: {} },
        source_dir: nil, source_sha256: nil
      )
      record
    end

    # Record a built target: platform becomes available, checksum recorded.
    def with_target(platform_id, checksum)
      available = available_targets.dup
      available << platform_id unless available.include?(platform_id)
      built = checksums[:built].dup
      built[platform_id.to_s] = checksum
      with(available_targets: available, checksums: checksums.merge(built: built))
    end

    def with_source(source_dir:, source_sha256:)
      with(
        source_dir: source_dir,
        source_sha256: source_sha256,
        checksums: checksums.merge(source: source_sha256)
      )
    end

    def with_checksum_source(sha)
      with(checksums: checksums.merge(source: sha))
    end

    # True when the package installs via lazy materialization (directory
    # source) — such packages must never serialize with a nil source_sha256,
    # or the install-time staleness gate cannot work.
    def materializable? = !targets.empty? && targets.all?(&:materializable?)

    # YAML-ready entry. Raises StateError when a materializable package
    # would serialize without a source fingerprint — the invariant that
    # makes skill-bundle re-materialization checks sound.
    def to_h
      if materializable? && source_sha256.nil?
        raise Rulepack::StateError,
              "source_sha256 missing for materializable package '#{pkgdesc || pkgver}' — cannot write build index"
      end

      h = {
        pkgver: pkgver, pkgrel: pkgrel, epoch: epoch, pkgdesc: pkgdesc,
        pkg_type: pkg_type, order: order,
        dependencies: dependencies, conflicts: conflicts, provides: provides,
        tags: tags,
        targets: targets.map(&:to_h),
        available_targets: available_targets.dup,
        checksums: { source: checksums[:source], built: checksums[:built].dup }
      }
      h[:source_dir] = source_dir if source_dir
      h[:source_sha256] = source_sha256 if source_sha256
      h
    end
  end
end
