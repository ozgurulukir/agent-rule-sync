# frozen_string_literal: true

module Rulepack
  module Common
    module_function

      # ─── Version Formatting ────────────────────────────────────────────────────

      # Format version as pacman-style string: "epoch:pkgver-pkgrel"
      # epoch 0 is omitted: "1.0.0-1" instead of "0:1.0.0-1"
      def format_version(epoch, pkgver, pkgrel)
        if epoch.to_i > 0
          "#{epoch}:#{pkgver}-#{pkgrel}"
        else
          "#{pkgver}-#{pkgrel}"
        end
      end
      # Supports alphanumeric segments: 1.2.3a < 1.2.3b < 1.2.4
      # Also handles epoch: pkgrel comparison when pkgver equal
      def compare_versions(v1, v2, pkgrel1: nil, pkgrel2: nil, epoch1: 0, epoch2: 0)
        # Epoch comparison (highest priority)
        cmp = epoch1 <=> epoch2
        return cmp unless cmp.zero?

        # pkgver comparison (alphanumeric segments)
        cmp = vercmp(v1, v2)
        return cmp unless cmp.zero?

        # pkgrel comparison (only if both provided)
        if pkgrel1.nil? || pkgrel2.nil?
          return 0  # no pkgrel info → equal
        end
        pkgrel1 <=> pkgrel2
      end

      # VerCmp implementation: split into alphanumeric segments
      # "1.2.3a" → [1, 2, "3a"]
      # Returns -1, 0, 1
      def vercmp(a, b)
        # Split on non-alphanumeric boundaries, keep runs of digits vs letters
        seg_a = a.to_s.scan(/\d+|[a-zA-Z]+|[^a-zA-Z0-9]+/).map { |s| s =~ /^\d+$/ ? s.to_i : s }
        seg_b = b.to_s.scan(/\d+|[a-zA-Z]+|[^a-zA-Z0-9]+/).map { |s| s =~ /^\d+$/ ? s.to_i : s }

        # Compare segment by segment
        [seg_a.size, seg_b.size].max.times do |i|
          sa = seg_a[i] || 0
          sb = seg_b[i] || 0

          # Both numeric → integer compare
          if sa.is_a?(Integer) && sb.is_a?(Integer)
            cmp = sa <=> sb
          elsif sa.is_a?(Integer) && !sb.is_a?(Integer)
            # Numeric < alphabetic (pacman: 1 < 1a)
            cmp = -1
          elsif !sa.is_a?(Integer) && sb.is_a?(Integer)
            cmp = 1
          else
            # Both strings: locale compare
            cmp = sa.to_s <=> sb.to_s
          end
          return cmp unless cmp.zero?
        end
        0
      end
    end
end
