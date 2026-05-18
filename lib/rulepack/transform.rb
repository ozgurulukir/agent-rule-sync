# frozen_string_literal: true

module Rulepack
  module Common
    module_function

    # Apply a transformer to content
    # transformer: 'copy', 'strip-frontmatter', or 'custom:/path/to/transformer.rb'
    def apply_transformer(transformer, content, pkgname:)
      case transformer
      when 'copy'
        content
      when 'strip-frontmatter'
        Rulepack::Common.log_warn "strip-frontmatter transformer is deprecated; SchemaEngine handles this automatically via platform schema."
        strip_frontmatter(content)
      when /^custom:(.+)/
        custom_rel = Regexp.last_match(1)
        # Resolve relative to repo root (RULEPACK_ROOT)
        custom_path = if custom_rel.start_with?('/') || custom_rel.start_with?('~')
                        expand_user_path(custom_rel)
                      else
                        RULEPACK_ROOT.join(custom_rel)
                      end.cleanpath
        unless custom_path.exist?
          raise "Custom transformer not found: #{custom_path}. Verify the path in your PKGBUILD transformer field."
        end

        # Security: ensure transformer path is within repo (symlink attack prevention)
        real_path = custom_path.realpath
        unless real_path.to_s.start_with?(RULEPACK_ROOT.to_s + File::SEPARATOR) || real_path == RULEPACK_ROOT
          raise "Custom transformer path outside repo (symlink attack?): #{custom_path}"
        end

        abs_path = real_path.to_s
        $LOADED_FEATURES.delete(abs_path)
        require abs_path

        transformer_klass = if defined?(RulepackTransformer::Impl)
                              RulepackTransformer::Impl
                            elsif defined?(Transform)
                              Transform
                            else
                              nil
                            end

        if transformer_klass.nil? || !transformer_klass.respond_to?(:transform)
          raise "Custom transformer #{custom_path} must define RulepackTransformer::Impl.transform(content, pkgname: nil) or Transform.transform method"
        end

        transformer_klass.transform(content, pkgname: pkgname)
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
                        RULEPACK_ROOT.join(custom_rel)
                      end.cleanpath
        unless custom_path.exist?
          raise "Custom translator not found: #{custom_path}. Verify the path in your PKGBUILD translate field."
        end

        real_path = custom_path.realpath
        unless real_path.to_s.start_with?(RULEPACK_ROOT.to_s + File::SEPARATOR) || real_path == RULEPACK_ROOT
          raise "Custom translator path outside repo (symlink attack?): #{custom_path}"
        end

        abs_path = real_path.to_s
        $LOADED_FEATURES.delete(abs_path)
        require abs_path

        translator_klass = if defined?(RulepackTranslator::Impl)
                             RulepackTranslator::Impl
                           elsif defined?(Translator)
                             Translator
                           else
                             nil
                           end

        if translator_klass.nil? || !translator_klass.respond_to?(:translate)
          raise "Custom translator #{custom_path} must define RulepackTranslator::Impl.translate(content, args: {}) or Translator.translate method"
        end

        translator_klass.translate(content, args: { pkgname: pkgname })
      else
        raise "Unknown translator: #{translator_cfg}"
      end
    end
  end
end
