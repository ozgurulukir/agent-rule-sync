# frozen_string_literal: true

require_relative 'helper'
require_relative '../lib/rulepack/build_pipeline'

class TestBuildPipeline < Minitest::Test
  def setup
    @sample_content = <<~MD
      ---
      title: Test Rule
      ---
      # Rule Header
      Here is some text with emojis 🚀✨🔥 and normal text.
    MD
  end

  def test_sequential_stages_advance_successfully
    pipeline = Rulepack::BuildPipeline.new(
      @sample_content,
      platform_id: 'opencode',
      pkgname: 'test-pkg',
      target_format: 'directory',
      format_profile: {}
    )

    assert_equal :fetch, pipeline.current_stage
    assert_equal [:fetch], pipeline.stage_log

    pipeline.advance(:translate) do
      assert_equal :translate, pipeline.current_stage
    end

    pipeline.advance(:schema_engine) do
      assert_equal :schema_engine, pipeline.current_stage
    end

    pipeline.advance(:transform) do
      assert_equal :transform, pipeline.current_stage
    end

    assert_equal %i[fetch translate schema_engine transform], pipeline.stage_log
  end

  def test_invalid_stage_transition_raises_error
    pipeline = Rulepack::BuildPipeline.new(
      @sample_content,
      platform_id: 'opencode',
      pkgname: 'test-pkg',
      target_format: 'directory',
      format_profile: {}
    )

    # Cannot jump to transform before translate and schema_engine
    assert_raises(RuntimeError) do
      pipeline.advance(:transform) do
        # Should not get here
      end
    end
  end

  def test_unknown_stage_raises_error
    pipeline = Rulepack::BuildPipeline.new(
      @sample_content,
      platform_id: 'opencode',
      pkgname: 'test-pkg',
      target_format: 'directory',
      format_profile: {}
    )

    assert_raises(RuntimeError) do
      pipeline.advance(:nonexistent_stage) do
        # Should not get here
      end
    end
  end

  def test_resolve_translator_uses_platform_registry_default
    platform_cfg = { type: 'skill', default_translator: 'custom:data/translators/rule_to_skill.rb' }

    result = Rulepack::SchemaEngine.resolve_translator(nil, 'crush', 'skill', platform_cfg)
    assert_equal 'custom:data/translators/rule_to_skill.rb', result
  end

  def test_resolve_translator_explicit_pkbuild_overrides_registry
    platform_cfg = { type: 'skill', default_translator: 'custom:data/translators/rule_to_skill.rb' }

    result = Rulepack::SchemaEngine.resolve_translator('custom:data/translators/my-translator.rb', 'crush', 'skill', platform_cfg)
    assert_equal 'custom:data/translators/my-translator.rb', result
  end

  def test_resolve_translator_returns_nil_when_no_default
    platform_cfg = { type: 'directory', default_translator: nil }

    result = Rulepack::SchemaEngine.resolve_translator(nil, 'opencode', 'directory', platform_cfg)
    assert_nil result
  end

  def test_resolve_transformer_uses_platform_registry_default
    platform_cfg = { type: 'skill', default_transformer: 'custom:data/transformers/my-transform.rb' }

    result = Rulepack::SchemaEngine.resolve_transformer(nil, 'crush', 'skill', platform_cfg)
    assert_equal 'custom:data/transformers/my-transform.rb', result
  end

  def test_resolve_transformer_falls_back_to_copy
    platform_cfg = { type: 'directory' }

    result = Rulepack::SchemaEngine.resolve_transformer(nil, 'opencode', 'directory', platform_cfg)
    assert_equal 'copy', result
  end

  def test_pipeline_runs_stages_correctly
    format_profile = {
      rules: {
        frontmatter: 'strip',
        emoji_policy: 'strip'
      }
    }
    platform_cfg = { type: 'directory' }

    pipeline = Rulepack::BuildPipeline.new(
      @sample_content,
      platform_id: 'opencode',
      pkgname: 'test-pkg',
      target_format: 'directory',
      format_profile: format_profile
    )

    processed_content = pipeline.run(platform_cfg)

    # Frontmatter should be stripped natively or by pipeline early strip
    refute_match(/---/, processed_content)
    # Emojis should be stripped by SchemaEngine during pipeline run
    refute_match(/🚀✨🔥/, processed_content)
    # Stages should have advanced sequentially
    assert_equal %i[fetch translate schema_engine transform], pipeline.stage_log
  end
end
