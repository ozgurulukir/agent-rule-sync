# frozen_string_literal: true

require_relative 'common'
require_relative 'schema_engine'

module Rulepack
  class BuildPipeline
    STAGES = %i[fetch translate schema_engine transform].freeze

    attr_reader :current_stage, :content, :platform_id, :pkgname, :target_format, :format_profile, :transformer, :stage_log

    def initialize(content, platform_id:, pkgname:, target_format:, format_profile:, transformer: 'copy', explicit_translate: nil, explicit_transformer: nil)
      @content = content
      @platform_id = platform_id.to_s
      @pkgname = pkgname.to_s
      @target_format = target_format.to_s
      @format_profile = format_profile || {}
      # explicit_transformer: 'copy' means "no-op" (PKGBUILD said copy)
      # nil means "not specified" → use schema default
      @explicit_transformer = explicit_transformer
      @explicit_translate = explicit_translate
      @current_stage = :fetch
      @stage_log = [:fetch]
    end

    # Advance stage to target_stage and execute block
    def advance(target_stage)
      expected_index = STAGES.index(target_stage)
      unless expected_index
        raise "Unknown build pipeline stage: #{target_stage}"
      end

      current_index = STAGES.index(@current_stage)
      if expected_index != current_index + 1
        raise "Invalid pipeline stage transition: #{@current_stage} -> #{target_stage}. Stages must run sequentially: #{STAGES.join(' -> ')}"
      end

      @current_stage = target_stage
      @stage_log << target_stage
      yield
    end

    # Run the full pipeline
    def run(platform_cfg)
      # ─── TRANSLATE STAGE ──────────────────────────────────────────────────
      advance(:translate) do
        translator_cfg = Rulepack::SchemaEngine.resolve_translator(@explicit_translate, @platform_id, @target_format)
        if translator_cfg
          Rulepack::Common.log "  → Translating for #{@platform_id} (#{translator_cfg})"
          puts "  → Translating for #{@platform_id} (#{translator_cfg})"
          @content = Rulepack::Common.apply_translator(translator_cfg, @content, pkgname: @pkgname)
          Rulepack::Common.log "    ✓ Translated (#{translator_cfg})"
          puts "    ✓ Translated (#{translator_cfg})"
        end
      end

      # ─── SCHEMA ENGINE STAGE ──────────────────────────────────────────────
      advance(:schema_engine) do
        @content = Rulepack::SchemaEngine.apply(@content, @format_profile, @target_format)
      end

      # ─── TRANSFORM STAGE ──────────────────────────────────────────────────
      advance(:transform) do
        transformer_cfg = Rulepack::SchemaEngine.resolve_transformer(@explicit_transformer, @platform_id, @target_format)
        if transformer_cfg && transformer_cfg != 'copy'
          Rulepack::Common.log "  → Transforming for #{@platform_id} (#{transformer_cfg})"
          puts "  → Transforming for #{@platform_id} (#{transformer_cfg})"
          @content = Rulepack::Common.apply_transformer(transformer_cfg, @content, pkgname: @pkgname)
          Rulepack::Common.log "    ✓ Transformed (#{transformer_cfg})"
          puts "    ✓ Transformed (#{transformer_cfg})"
        end
      end

      @content
    end
  end
end
