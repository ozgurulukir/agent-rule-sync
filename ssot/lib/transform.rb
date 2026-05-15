# frozen_string_literal: true

module Ssot
  module Lib
    module Common
      module_function

      # Apply a transformer to content
      # transformer: 'copy', 'strip-frontmatter', or 'custom:/path/to/transformer.rb'
      def apply_transformer(transformer, content, pkgname:)
        case transformer
        when 'copy'
          content
        when 'strip-frontmatter'
          strip_frontmatter(content)
        when /^custom:(.+)/
          custom_rel = Regexp.last_match(1)
          # Resolve relative to repo root (SSOT_ROOT)
          custom_path = if custom_rel.start_with?('/') || custom_rel.start_with?('~')
                          expand_user_path(custom_rel)
                        else
                          SSOT_ROOT.join(custom_rel)
                        end.cleanpath
          unless custom_path.exist?
            raise "Custom transformer not found: #{custom_path}. Verify the path in your PKGBUILD transformer field."
          end
          # Security: ensure transformer path is within repo (symlink attack prevention)
          real_path = custom_path.realpath
          unless real_path.to_s.start_with?(SSOT_ROOT.to_s + File::SEPARATOR) || real_path == SSOT_ROOT
            raise "Custom transformer path outside repo (symlink attack?): #{custom_path}"
          end
          abs_path = real_path.to_s
          $LOADED_FEATURES.delete(abs_path)
          require abs_path
          unless defined?(Transform) && Transform.respond_to?(:transform)
            raise "Custom transformer #{custom_path} must define Transform.transform(content, pkgname: nil) method"
          end
          Transform.transform(content, pkgname: pkgname)
        else
          raise "Unknown transformer: #{transformer}"
        end
      end

      # Remove YAML frontmatter (--- ... ---) from content
      def strip_frontmatter(content)
        content.sub(/\A---\s*\n.*?\n---\s*\n/m, '')
      end

      # ─── Translate Layer ─────────────────────────────────────────────────────
      # Translator: platform-specific content conversion (markdown dialect, format family).
      # Runs BEFORE transformer. Translators read content + optional args, return translated content.
      # Built-in: 'copy' (identity), 'identity'
      # Custom: 'custom:<relative/path/to/translator.rb>' — must define Translator.translate(content, args: {})
      def apply_translator(translator_cfg, content, pkgname:)
        return content unless translator_cfg

        case translator_cfg
        when 'copy', 'identity', nil
          content
        when /^custom:(.+)/
          custom_rel = Regexp.last_match(1)
          custom_path = if custom_rel.start_with?('/') || custom_rel.start_with?('~')
                          expand_user_path(custom_rel)
                        else
                          SSOT_ROOT.join(custom_rel)
                        end.cleanpath
          unless custom_path.exist?
            raise "Custom translator not found: #{custom_path}. Verify the path in your PKGBUILD translate field."
          end
          real_path = custom_path.realpath
          unless real_path.to_s.start_with?(SSOT_ROOT.to_s + File::SEPARATOR) || real_path == SSOT_ROOT
            raise "Custom translator path outside repo (symlink attack?): #{custom_path}"
          end
          abs_path = real_path.to_s
          $LOADED_FEATURES.delete(abs_path)
          require abs_path
          unless defined?(Translator) && Translator.respond_to?(:translate)
            raise "Custom translator #{custom_path} must define Translator.translate(content, args: {}) method"
          end
          Translator.translate(content, args: { pkgname: pkgname })
        else
          raise "Unknown translator: #{translator_cfg}"
        end
      end
    end
  end
end
