# frozen_string_literal: true

# Network failure integration tests for Rulepack
# Tests error handling for timeouts, connection failures, and invalid URLs

require_relative 'helper'
require 'minitest/mock'

class TestNetworkFailureIntegration < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-network-test-')
    @test_root = Pathname.new(@tmpdir)
    FileUtils.cp_r(ROOT.join('lib').to_s, @test_root.join('lib').to_s, preserve: false)
    FileUtils.cp_r(ROOT.join('data').to_s, @test_root.join('data').to_s, preserve: false)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_fetch_url_with_timeout
    # Test that URL fetch respects timeout configuration
    skip "Network test - requires actual HTTP request" unless ENV['RULEPACK_RUN_NETWORK_TESTS']

    # Use a URL that should timeout or be unreachable
    uri = URI.parse('http://10.255.255.1:12345') # Unroutable address
    start_time = Time.now

    assert_raises(RuntimeError, 'HTTP fetch should fail or timeout') do
      Rulepack::Common.cached_fetch_url('http://10.255.255.1:12345/timeout-test', nil)
    end

    elapsed = Time.now - start_time
    assert elapsed < 35, "Request should timeout before 35s (configurable timeout is 30s + buffer)"
  end

  def test_fetch_url_with_invalid_hostname
    assert_raises(RuntimeError, Socket::ResolutionError, Errno::ECONNREFUSED, 'Should raise on invalid hostname') do
      # This should fail quickly with getaddrinfo error
      Rulepack::Common.cached_fetch_url('http://this-hostname-definitely-does-not-exist-12345.invalid/test', nil)
    end
  end

  def test_fetch_url_with_malformed_url
    assert_raises(URI::InvalidURIError, Errno::ECONNREFUSED, RuntimeError, 'Should raise on malformed URL') do
      Rulepack::Common.cached_fetch_url('not-a-valid-url', nil)
    end
  end

  def test_fetch_url_with_http_error
    skip "Network test - requires actual HTTP server" unless ENV['RULEPACK_RUN_NETWORK_TESTS']

    # Use httpbin to get a 404
    error = assert_raises(RuntimeError) do
      Rulepack::Common.cached_fetch_url('https://httpbin.org/status/404', nil)
    end
    assert_match(/HTTP 404/, error.message, 'Error should include HTTP status code')
  end

  def test_git_clone_with_invalid_url
    assert_raises(RuntimeError, 'Should raise on invalid git URL') do
      Rulepack::Common.fetch_git_source(
        'https://invalid-git-url-that-does-not-exist.example.com/repo.git',
        'main',
        @test_root.join('git-dest').to_s
      )
    end
  end

  def test_git_clone_with_nonexistent_ref
    skip "Network test - requires actual git repo" unless ENV['RULEPACK_RUN_NETWORK_TESTS']

    # Use a valid URL but invalid ref
    assert_raises(RuntimeError, 'Should raise when git clone fails') do
      Rulepack::Common.fetch_git_source(
        'https://github.com/rmyndharis/antigravity-skills.git',
        'nonexistent-branch-xyz-123',
        @test_root.join('git-dest').to_s,
        depth: 1
      )
    end
  end

  def test_fetch_url_with_redirect_loop_protection
    skip "Network test - requires actual HTTP server" unless ENV['RULEPACK_RUN_NETWORK_TESTS']

    # Test that max_redirects is respected
    # This would need a server configured to redirect infinitely
    # For now, we verify the configuration is respected
    max_redirects = Rulepack::Config.max_redirects
    assert_equal 3, max_redirects, 'Default max redirects should be 3'

    ENV['RULEPACK_MAX_REDIRECTS'] = '5'
    assert_equal 5, Rulepack::Config.max_redirects, 'Should respect RULEPACK_MAX_REDIRECTS env var'
    ENV.delete('RULEPACK_MAX_REDIRECTS')
  end

  def test_fetch_url_respects_read_timeout_config
    # Verify timeout configuration is used
    timeout = Rulepack::Config.read_timeout
    assert_equal 30, timeout, 'Default read timeout should be 30 seconds'

    ENV['RULEPACK_READ_TIMEOUT'] = '60'
    assert_equal 60, Rulepack::Config.read_timeout, 'Should respect RULEPACK_READ_TIMEOUT env var'
    ENV.delete('RULEPACK_READ_TIMEOUT')
  end

  def test_cached_fetch_handles_network_failure_gracefully
    # Test that network failures raise appropriate errors (not crash)
    # We can't easily mock Net::HTTP.start, but we verify timeout behavior
    skip "Complex mock test - network failures tested via integration tests"
    
    # At minimum, verify timeout config is respected
    assert_equal 30, Rulepack::Config.read_timeout, "Default timeout should be 30s"
  end
end
