# frozen_string_literal: true

require_relative 'helper'
require_relative '../lib/rulepack/installer'

class TestTuiSelector < Minitest::Test
  def setup
    @sub_skills = [
      { 'name' => 'skill-one', 'path' => 'one' },
      { 'name' => 'skill-two', 'path' => 'two' },
      { 'name' => 'skill-three', 'path' => 'three' }
    ]
  end

  def test_select_sub_skills_with_explicit_array
    # Should filter by array names
    selected = Rulepack::Install.select_sub_skills(@sub_skills, ['skill-one', 'skill-three'], 'test-pkg')
    assert_equal 2, selected.size
    assert_equal 'skill-one', selected[0]['name']
    assert_equal 'skill-three', selected[1]['name']
  end

  def test_select_sub_skills_with_no_match
    # Should log warning and return nil
    selected = Rulepack::Install.select_sub_skills(@sub_skills, ['nonexistent'], 'test-pkg')
    assert_nil selected
  end

  def test_select_sub_skills_not_interactive_in_tests
    # $stdin.isatty is false in test environments, so prompt_sub_skill_selection should return original list
    selected = Rulepack::Install.select_sub_skills(@sub_skills, :interactive, 'test-pkg')
    assert_equal @sub_skills.size, selected.size
  end

  def test_select_sub_skills_default_behavior_non_tty
    # In non-TTY test environments, without select list, it should return all
    selected = Rulepack::Install.select_sub_skills(@sub_skills, nil, 'test-pkg')
    assert_equal @sub_skills.size, selected.size
  end
end
