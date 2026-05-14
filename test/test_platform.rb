# frozen_string_literal: true

# Unit tests for platform registry, path resolution, and related helpers
# Covers: load_platform_registry, validate_platform_config, platform_config,
#         resolve_install_path, safe_relative, build_dir_for_platform,
#         check_prerequisites

require_relative 'helper'

# ─── load_platform_registry ────────────────────────────────────────────────────

class TestLoadPlatformRegistry < Minitest::Test
  def test_loads_registry_successfully
    registry = Ssot::Lib::Common.load_platform_registry
    assert registry.is_a?(Hash), 'Registry should be a Hash'
    assert registry.key?(:opencode), 'Registry should contain opencode'
    assert registry.key?(:crush), 'Registry should contain crush'
  end

  def test_registry_has_all_expected_platforms
    registry = Ssot::Lib::Common.load_platform_registry
    expected = %i[opencode oh-my-pi crush goose droid gemini-cli qwen-code cursor windsurf github-copilot claude-code codex]
    expected.each do |p|
      assert registry.key?(p), "Registry should contain #{p}"
    end
  end

  def test_each_platform_has_type
    registry = Ssot::Lib::Common.load_platform_registry
    registry.each do |id, cfg|
      assert cfg[:type], "Platform #{id} should have :type"
      assert_includes %w[directory import skill], cfg[:type], "Platform #{id} type should be valid"
    end
  end

  def test_each_platform_has_base_path
    registry = Ssot::Lib::Common.load_platform_registry
    registry.each do |id, cfg|
      assert cfg[:base_path], "Platform #{id} should have :base_path"
    end
  end
end

# ─── validate_platform_config ──────────────────────────────────────────────────

class TestValidatePlatformConfig < Minitest::Test
  def test_valid_directory_platform_does_not_raise
    cfg = { type: 'directory', base_path: '/tmp/test', rules_dir: 'rules/', skills_dir: 'skills/', rule_install: { type: 'symlink' }, skill_install: { type: 'copy' } }
    Ssot::Lib::Common.validate_platform_config(:test, cfg)
    pass 'directory platform validated without error'
  end

  def test_valid_import_platform_does_not_raise
    cfg = { type: 'import', base_path: '/tmp/test', config_file: 'config.yaml' }
    Ssot::Lib::Common.validate_platform_config(:test, cfg)
    pass 'import platform validated without error'
  end

  def test_valid_skill_platform_does_not_raise
    cfg = { type: 'skill', base_path: '/tmp/test', skill_file: 'agent.md' }
    Ssot::Lib::Common.validate_platform_config(:test, cfg)
    pass 'skill platform validated without error'
  end

  def test_raises_on_missing_type
    error = assert_raises(RuntimeError) { Ssot::Lib::Common.validate_platform_config(:test, { base_path: '/tmp' }) }
    assert_match(/missing required field.*type/, error.message)
  end

  def test_raises_on_missing_base_path
    error = assert_raises(RuntimeError) { Ssot::Lib::Common.validate_platform_config(:test, { type: 'directory' }) }
    assert_match(/missing required field.*base_path/, error.message)
  end

  def test_raises_on_directory_missing_rules_dir
    error = assert_raises(RuntimeError) { Ssot::Lib::Common.validate_platform_config(:test, { type: 'directory', base_path: '/tmp' }) }
    assert_match(/missing :rules_dir/, error.message)
  end

  def test_raises_on_import_missing_config_file
    error = assert_raises(RuntimeError) { Ssot::Lib::Common.validate_platform_config(:test, { type: 'import', base_path: '/tmp' }) }
    assert_match(/missing :config_file/, error.message)
  end

  def test_raises_on_skill_missing_skill_file
    error = assert_raises(RuntimeError) { Ssot::Lib::Common.validate_platform_config(:test, { type: 'skill', base_path: '/tmp' }) }
    assert_match(/missing :skill_file/, error.message)
  end

  def test_raises_on_unknown_type
    error = assert_raises(RuntimeError) { Ssot::Lib::Common.validate_platform_config(:test, { type: 'unknown', base_path: '/tmp' }) }
    assert_match(/unknown type/, error.message)
  end
end

# ─── platform_config ───────────────────────────────────────────────────────────

class TestPlatformConfig < Minitest::Test
  def setup
    @registry = Ssot::Lib::Common.load_platform_registry
  end

  def test_lookup_by_string_name
    cfg = Ssot::Lib::Common.platform_config('opencode', @registry)
    assert cfg, 'Should find opencode by string name'
    assert_equal 'directory', cfg[:type]
  end

  def test_lookup_by_symbol_name
    cfg = Ssot::Lib::Common.platform_config(:opencode, @registry)
    assert cfg, 'Should find opencode by symbol name'
    assert_equal 'directory', cfg[:type]
  end

  def test_lookup_hyphenated_platform_by_symbol
    cfg = Ssot::Lib::Common.platform_config(:"gemini-cli", @registry)
    assert cfg, 'Should find gemini-cli by hyphenated symbol'
    assert_equal 'import', cfg[:type]
  end

  def test_raises_on_unknown_platform_string
    assert_raises(RuntimeError, /Unknown platform/) do
      Ssot::Lib::Common.platform_config('nonexistent', @registry)
    end
  end

  def test_raises_on_unknown_platform_symbol
    assert_raises(RuntimeError, /Unknown platform/) do
      Ssot::Lib::Common.platform_config(:nonexistent, @registry)
    end
  end
end

# ─── resolve_install_path ──────────────────────────────────────────────────────

class TestResolveInstallPath < Minitest::Test
  def setup
    @registry = Ssot::Lib::Common.load_platform_registry
  end

  def test_resolves_directory_platform_path
    platform_cfg = @registry[:opencode]
    target_cfg = { format: 'directory', output: '00-memory.md' }
    path = Ssot::Lib::Common.resolve_install_path(platform_cfg, target_cfg)
    assert_kind_of Pathname, path
    assert_match(/rules\//, path.to_s)
    assert_match(/00-memory\.md/, path.to_s)
  end

  def test_resolves_skill_platform_path
    platform_cfg = @registry[:crush]
    target_cfg = { format: 'skill', output: 'memory-skill.md' }
    path = Ssot::Lib::Common.resolve_install_path(platform_cfg, target_cfg)
    assert_kind_of Pathname, path
    assert_match(/crush\.md/, path.to_s)
  end

  def test_resolves_import_platform_path
    platform_cfg = @registry[:"gemini-cli"]
    target_cfg = { format: 'import', output: 'memory-rule.md' }
    path = Ssot::Lib::Common.resolve_install_path(platform_cfg, target_cfg)
    assert_kind_of Pathname, path
    assert_match(/cli_config\.yaml/, path.to_s)
  end

  def test_resolves_with_base_override
    platform_cfg = @registry[:opencode]
    target_cfg = { format: 'directory', output: '00-memory.md' }
    override = Pathname.new('/custom/project')
    path = Ssot::Lib::Common.resolve_install_path(platform_cfg, target_cfg, override)
    assert_kind_of Pathname, path
    assert path.to_s.start_with?('/custom/project'), "Should use override base: #{path}"
  end

  def test_skill_format_uses_skills_dir
    platform_cfg = @registry[:opencode]
    target_cfg = { format: 'skill', output: 'my-skill.md' }
    path = Ssot::Lib::Common.resolve_install_path(platform_cfg, target_cfg)
    assert_match(/skills\//, path.to_s, 'skill format should use skills_dir')
  end
end

# ─── safe_relative ─────────────────────────────────────────────────────────────

class TestSafeRelative < Minitest::Test
  def test_returns_relative_path_within_base
    base = Pathname.new('/home/user/project')
    child = Pathname.new('/home/user/project/subdir/file.md')
    rel = Ssot::Lib::Common.safe_relative(child, base)
    assert_equal 'subdir/file.md', rel
  end

  def test_returns_dot_for_same_path
    base = Pathname.new('/home/user/project')
    rel = Ssot::Lib::Common.safe_relative(base, base)
    assert_equal '.', rel
  end

  def test_raises_on_path_escaping_parent
    base = Pathname.new('/home/user/project')
    outside = Pathname.new('/home/user/other/file.md')
    assert_raises(RuntimeError, /escapes base/) do
      Ssot::Lib::Common.safe_relative(outside, base)
    end
  end
end

# ─── build_dir_for_platform ────────────────────────────────────────────────────

class TestBuildDirForPlatform < Minitest::Test
  def test_returns_correct_build_path
    path = Ssot::Lib::Common.build_dir_for_platform('opencode')
    assert_equal Pathname.new('ssot/build/opencode'), path
  end

  def test_returns_pathname_for_all_platforms
    %w[opencode crush cursor].each do |platform|
      path = Ssot::Lib::Common.build_dir_for_platform(platform)
      assert_kind_of Pathname, path
      assert_equal "ssot/build/#{platform}", path.to_s
    end
  end
end

# ─── check_prerequisites ──────────────────────────────────────────────────────

class TestCheckPrerequisites < Minitest::Test
  def setup
    @registry = Ssot::Lib::Common.load_platform_registry
  end

  def test_returns_empty_array_when_all_tools_present
    result = Ssot::Lib::Common.check_prerequisites(@registry[:opencode])
    assert_kind_of Array, result
    refute_includes result, 'ruby', 'ruby should be available in test env'
  end

  def test_returns_missing_tools_in_array
    fake_cfg = { prerequisites: { tools: ['__nonexistent_tool_xyz__'] } }
    result = Ssot::Lib::Common.check_prerequisites(fake_cfg)
    assert_includes result, '__nonexistent_tool_xyz__'
  end

  def test_returns_empty_for_empty_prerequisites
    result = Ssot::Lib::Common.check_prerequisites({})
    assert_empty result
  end

  def test_returns_empty_when_tools_is_nil
    result = Ssot::Lib::Common.check_prerequisites(prerequisites: { tools: nil })
    assert_empty result
  end

  def test_checks_multiple_tools
    fake_cfg = { prerequisites: { tools: ['__nonexistent_a__', '__nonexistent_b__'] } }
    result = Ssot::Lib::Common.check_prerequisites(fake_cfg)
    assert_includes result, '__nonexistent_a__'
    assert_includes result, '__nonexistent_b__'
  end
end
