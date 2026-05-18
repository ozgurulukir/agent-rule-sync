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

  def test_auto_derive_translator_for_skill_platform
    platform_cfg = { type: 'skill' }

    # When target format is skill/skill-bundle and platform type is skill, should use custom translator
    result1 = Rulepack::SchemaEngine.auto_derive_translator(platform_cfg, 'skill')
    assert_equal 'custom:data/translators/rule_to_skill.rb', result1

    result2 = Rulepack::SchemaEngine.auto_derive_translator(platform_cfg, 'skill-bundle')
    assert_equal 'custom:data/translators/rule_to_skill.rb', result2

    # When target format is directory/import, should not translate (return nil)
    result3 = Rulepack::SchemaEngine.auto_derive_translator(platform_cfg, 'directory')
    assert_nil result3
  end

  def test_auto_derive_translator_for_non_skill_platform
    platform_cfg = { type: 'directory' }

    # Should not translate (return nil) even if target format is skill
    result = Rulepack::SchemaEngine.auto_derive_translator(platform_cfg, 'skill')
    assert_nil result
  end

  def test_auto_derive_transformer_is_always_copy
    format_profile = { rules: { frontmatter: 'strip' } }
    result = Rulepack::SchemaEngine.auto_derive_transformer(format_profile, 'directory')
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
