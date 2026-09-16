# frozen_string_literal: true

# Guards the explicit re-export contract of Rulepack::Common.
#
# Common is an explicit composition root: every submodule method re-exported
# there must keep existing (and keep passing blocks through). If you remove a
# re-export intentionally, delete its line here; if this test fails after
# refactoring a submodule's signature, update the re-export in common.rb.

require_relative 'helper'

class TestCommonFacade < Minitest::Test
  RE_EXPORTS = {
    'Rulepack::Platforms'  => %w[validate_platform_config validate_format_profile],
    'Rulepack::Logging'    => %w[log log_warn log_error log_debug time]
  }.freeze

  # Modules whose methods are NOT re-exported by Common — callers must use
  # the owning module directly (IO, Path, Validation, InstallHelpers were
  # de-facadeted in 2026-09; a re-export must not silently reappear).
  DE_FACADETED = {
    'Rulepack::IO'         => %w[load_yaml write_yaml_atomic atomic_write update_marked_content deep_merge],
    'Rulepack::Path'       => %w[expand_user_path strip_frontmatter],
    'Rulepack::Validation' => %w[load_pkgbuild validate_pkgbuild validate_targets_and_packages verify_checksum],
    'Rulepack::InstallHelpers' => %w[uninstall_packages migrate_installed_records]
  }.freeze

  def test_re_exported_methods_exist_and_delegate
    RE_EXPORTS.each do |owner, methods|
      mod = Object.const_get(owner)
      methods.each do |m|
        assert mod.respond_to?(m), "#{owner}.#{m} disappeared — common.rb re-export is dangling"
        assert Rulepack::Common.respond_to?(m), "Common.#{m} re-export missing"
      end
    end
  end

  def test_defacadeted_methods_stay_off_common
    DE_FACADETED.each do |owner, methods|
      mod = Object.const_get(owner)
      methods.each do |m|
        assert mod.respond_to?(m), "#{owner}.#{m} disappeared"
        refute Rulepack::Common.respond_to?(m), "Common.#{m} re-export must stay deleted — call #{owner}.#{m} directly"
      end
    end
  end

  def test_scoped_paths_reach_deep_readers
    tmp = Pathname.new(Dir.mktmpdir('rulepack-facade-'))
    Rulepack::Common.with_paths(build_index_path: tmp.join('custom-index.yaml')) do
      assert_equal tmp.join('custom-index.yaml'), Rulepack::Common.build_index_path
    end
  ensure
    FileUtils.rm_rf(tmp) if tmp
  end

  def test_scoped_paths_restore_after_block
    before = Rulepack::Common.build_index_path
    Rulepack::Common.with_paths(build_dir: Pathname.new(Dir.mktmpdir)) { }
    assert_equal before, Rulepack::Common.build_index_path, 'paths scope must not leak'
  end

  def test_scoped_ui_reaches_deep_readers
    null = Rulepack::UI::Null.new
    Rulepack::Common.with_ui(null) do
      assert_equal null, Rulepack::Common.ui
      assert_equal 'stop', Rulepack::Common.interactive_collision_prompt('/tmp/whatever')
    end
  end

  def test_ui_null_is_non_interactive
    ui = Rulepack::UI::Null.new
    refute ui.interactive?
    refute ui.confirm('anything')
    assert_equal 'stop', ui.collision_prompt('/tmp/whatever')
    assert_equal :ran, ui.spin('msg') { :ran }
  end
end
