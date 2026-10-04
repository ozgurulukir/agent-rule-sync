# frozen_string_literal: true

$LOAD_PATH.unshift File.join(File.expand_path('..', __dir__), 'lib')

require 'minitest/autorun'
require 'rulepack'
require_relative '../lib/rulepack/build_writer'
require_relative '../lib/rulepack/generate-catalog'

# BuildWriter output policy: the catalog write outcome must reach the caller
# (Build folds it into the Result status) instead of dying in a swallow-rescue
# or riding a clean exit 0 when the write was skipped.
class TestBuildWriter < Minitest::Test
  def test_generate_catalog_returns_true_when_written
    Rulepack::CatalogGenerator.stub(:main, -> { true }) do
      assert_equal true, Rulepack::BuildWriter.generate_catalog
    end
  end

  def test_generate_catalog_returns_false_when_skipped
    Rulepack::CatalogGenerator.stub(:main, -> { false }) do
      assert_equal false, Rulepack::BuildWriter.generate_catalog
    end
  end

  def test_generate_catalog_returns_false_on_failure
    Rulepack::CatalogGenerator.stub(:main, -> { raise 'catalog boom' }) do
      assert_equal false, Rulepack::BuildWriter.generate_catalog
    end
  end
end
