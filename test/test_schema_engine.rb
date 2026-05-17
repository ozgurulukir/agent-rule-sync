# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rulepack/common'
require_relative '../lib/rulepack/schema_engine'

class TestSchemaEngine < Minitest::Test
  def setup
    @sample_content = <<~MD
      ---
      title: Test Rule
      version: 1.0
      ---
      # Rule Header
      Here is some text with emojis 🚀✨🔥 and normal text.
    MD
  end

  def test_no_format_profile
    result = Rulepack::SchemaEngine.apply(@sample_content, nil, 'directory')
    assert_equal @sample_content, result
  end

  def test_empty_format_profile
    result = Rulepack::SchemaEngine.apply(@sample_content, {}, 'directory')
    assert_equal @sample_content, result
  end

  def test_rules_strip_frontmatter
    profile = { rules: { frontmatter: 'strip' } }
    result = Rulepack::SchemaEngine.apply(@sample_content, profile, 'directory')
    refute_match(/---/, result)
    assert_match(/# Rule Header/, result)
    assert_match(/🚀✨🔥/, result) # Emojis should be kept
  end

  def test_skills_strip_emojis
    profile = { skills: { emoji_policy: 'strip' } }
    result = Rulepack::SchemaEngine.apply(@sample_content, profile, 'skill')
    assert_match(/---/, result) # Frontmatter should be kept
    refute_match(/🚀✨🔥/, result)
    assert_match(/Here is some text with emojis  and normal text\./, result)
  end

  def test_both_strip_frontmatter_and_emojis
    profile = { rules: { frontmatter: 'strip', emoji_policy: 'strip' } }
    result = Rulepack::SchemaEngine.apply(@sample_content, profile, 'directory')
    refute_match(/---/, result)
    refute_match(/🚀✨🔥/, result)
    assert_match(/Here is some text with emojis  and normal text\./, result)
  end

  def test_setext_heading_conversion
    content = <<~MD
      My Main Header
      ==============
      My Sub Header
      -------------
      Some regular text.

      ---
      A horizontal rule above.
    MD
    profile = { rules: { heading_style: 'atx' } }
    result = Rulepack::SchemaEngine.apply(content, profile, 'directory')
    assert_match(/^# My Main Header$/, result)
    assert_match(/^## My Sub Header$/, result)
    assert_match(/^---$/, result) # Horizontal rule should be kept as-is
  end

  def test_bullet_style_conversion
    content = <<~MD
      * Star Bullet
      + Plus Bullet
        * Nested Bullet
      - Already Dash Bullet
    MD
    profile = { rules: { bullet_style: 'dash' } }
    result = Rulepack::SchemaEngine.apply(content, profile, 'directory')
    assert_match(/^- Star Bullet$/, result)
    assert_match(/^- Plus Bullet$/, result)
    assert_match(/^\s+- Nested Bullet$/, result)
    assert_match(/^- Already Dash Bullet$/, result)
  end

  def test_max_heading_depth_capping
    content = <<~MD
      # H1
      ## H2
      ### H3
      #### H4
      ##### H5
    MD
    profile = { rules: { max_heading_depth: 3 } }
    result = Rulepack::SchemaEngine.apply(content, profile, 'directory')
    assert_match(/^# H1$/, result)
    assert_match(/^## H2$/, result)
    assert_match(/^### H3$/, result)
    assert_match(/^### H4$/, result)
    assert_match(/^### H5$/, result)
  end
end
