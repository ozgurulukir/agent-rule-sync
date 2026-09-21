# frozen_string_literal: true

# Unit tests for the unified translator/transformer loader.

require_relative 'helper'

class TestProcessorLoader < Minitest::Test
  def test_load_translator_returns_namespaced_module
    processor = Rulepack::ProcessorLoader.load_translator('custom:data/translators/rule_to_skill.rb')
    assert_equal RulepackTranslator::RuleToSkill, processor
    assert_respond_to processor, :translate
  end

  def test_load_transformer_returns_namespaced_module
    processor = Rulepack::ProcessorLoader.load_transformer('custom:data/transformers/add_frontmatter.rb')
    assert_equal RulepackTransformer::AddFrontmatter, processor
    assert_respond_to processor, :transform
  end

  def test_load_custom_rejects_missing_file
    assert_raises(Rulepack::ConfigError) do
      Rulepack::ProcessorLoader.load_custom('custom:data/translators/nonexistent.rb', kind: :translator)
    end
  end

  def test_load_custom_rejects_path_outside_repo
    root = Rulepack::Common::RULEPACK_ROOT.realpath
    home = Pathname.new(Rulepack::Path.expand_user_path('~')).realpath
    skip 'home dir is inside the repo root; outside-repo rejection not testable here' if home.to_s.start_with?(root.to_s + File::SEPARATOR) || home == root

    fname = "rulepack_outside_test_#{Process.pid}.rb"
    outside = home.join(fname)
    outside.write('# fixture for outside-repo rejection')
    begin
      assert_raises(Rulepack::SecurityError) do
        Rulepack::ProcessorLoader.load_custom("custom:~/#{fname}", kind: :translator)
      end
    ensure
      outside.unlink if outside.exist?
    end
  end

  def test_each_translator_has_isolated_namespace
    rule_to_skill = Rulepack::ProcessorLoader.load_translator('custom:data/translators/rule_to_skill.rb')
    rule_to_import = Rulepack::ProcessorLoader.load_translator('custom:data/translators/rule_to_import.rb')

    refute_equal rule_to_skill, rule_to_import
    assert_equal RulepackTranslator::RuleToSkill, rule_to_skill
    assert_equal RulepackTranslator::RuleToImport, rule_to_import
  end
end
