# frozen_string_literal: true

require_relative 'processor_loader'

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
        raise ArgumentError, "strip-frontmatter transformer is permanently removed. Frontmatter is handled automatically by the SchemaEngine via platform schema (frontmatter: strip). Remove the transformer field from your PKGBUILD."
      when /^custom:(.+)/
        processor = Rulepack::ProcessorLoader.load_transformer(transformer)
        processor.transform(content, pkgname: pkgname)
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
    def apply_translator(translator_cfg, content, pkgname:, extra_args: {})
      return content unless translator_cfg

      case translator_cfg
      when 'copy', 'identity', nil
        content
      when /^custom:(.+)/
        processor = Rulepack::ProcessorLoader.load_translator(translator_cfg)
        processor.translate(content, args: { pkgname: pkgname }.merge(extra_args))
      else
        raise "Unknown translator: #{translator_cfg}"
      end
    end
  end
end
