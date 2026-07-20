# frozen_string_literal: true

require_relative 'helper'
require_relative '../lib/rulepack/lib/install_handlers'

class TestInstallHandlers < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-handlers-test-')
    @ctx = Struct.new(:dry_run, :collision_strategy, :quiet, :journal).new(false, 'overwrite', true, [])
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_do_structured_inject_yaml
    install_path = Pathname.new(@tmpdir).join('config.yaml')
    platform_cfg = { rule_install: { directive: '@import', inject_key: 'imports', format: 'yaml' } }

    Rulepack::InstallHandlers.do_structured_inject(install_path, platform_cfg, 'rules.md', 'test-pkg', @ctx)

    assert install_path.exist?
    data = YAML.safe_load(install_path.read, permitted_classes: [Symbol], symbolize_names: true)
    assert_equal ['@import "rules.md"'], data[:imports]

    # Test idempotency
    Rulepack::InstallHandlers.do_structured_inject(install_path, platform_cfg, 'rules.md', 'test-pkg', @ctx)
    data = YAML.safe_load(install_path.read, permitted_classes: [Symbol], symbolize_names: true)
    assert_equal ['@import "rules.md"'], data[:imports]
  end

  def test_do_structured_inject_json
    install_path = Pathname.new(@tmpdir).join('config.json')
    platform_cfg = { rule_install: { directive: '@import', inject_key: 'imports', format: 'json' } }

    Rulepack::InstallHandlers.do_structured_inject(install_path, platform_cfg, 'rules.md', 'test-pkg', @ctx)

    assert install_path.exist?
    data = JSON.parse(install_path.read)
    assert_equal ['@import "rules.md"'], data['imports']
  end
end
