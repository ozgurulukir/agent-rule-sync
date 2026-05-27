# frozen_string_literal: true

require_relative 'helper'
require 'socket'
require 'minitest/mock'

class TestNetworkFailureIntegration < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rulepack-network-test-')
    @test_root = Pathname.new(@tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_fetch_url_with_unroutable_address
    TCPServer.new('127.0.0.1', 0) do |srv|
      port = srv.addr[1]
      srv.close
      error = assert_raises(RuntimeError) do
        Rulepack::Common.cached_fetch_url("http://10.255.255.1:#{port}/test", nil)
      end
      assert_match(/Failed to fetch|timeout|refused|Network|not known/i, error.message)
    end
  end

  def test_fetch_url_with_invalid_hostname
    assert_raises(RuntimeError, Socket::ResolutionError, Errno::ECONNREFUSED, 'Should raise on invalid hostname') do
      Rulepack::Common.cached_fetch_url('http://this-hostname-definitely-does-not-exist-12345.invalid/test', nil)
    end
  end

  def test_fetch_url_with_malformed_url
    assert_raises(URI::InvalidURIError, Errno::ECONNREFUSED, RuntimeError, 'Should raise on malformed URL') do
      Rulepack::Common.cached_fetch_url('not-a-valid-url', nil)
    end
  end

  def test_fetch_url_with_http_error
    TCPServer.new('127.0.0.1', 0) do |srv|
      port = srv.addr[1]
      thread = Thread.new do
        client = srv.accept
        client.gets
        client.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
        client.close
      end

      error = assert_raises(RuntimeError) do
        Rulepack::Common.cached_fetch_url("http://127.0.0.1:#{port}/test", nil)
      end
      assert_match(/Failed to fetch.*404/i, error.message)
      thread.join
    end
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
    local_repo = @test_root.join('local-repo')
    local_repo.mkpath
    system('git', 'init', '--quiet', local_repo.to_s, out: File::NULL, err: File::NULL)
    system('git', '-C', local_repo.to_s, 'commit', '--allow-empty', '-m', 'init',
           out: File::NULL, err: File::NULL)

    dest = @test_root.join('git-dest').to_s
    error = assert_raises(RuntimeError) do
      Rulepack::Common.fetch_git_source(
        "file://#{local_repo}",
        'nonexistent-branch-xyz-123',
        dest,
        depth: 1
      )
    end
    assert_match(/failed|error|cannot/i, error.message)
  end

  def test_fetch_url_with_redirect_loop_protection
    max_redirects = Rulepack::Config.max_redirects
    assert_equal 3, max_redirects, 'Default max redirects should be 3'

    ENV['RULEPACK_MAX_REDIRECTS'] = '5'
    assert_equal 5, Rulepack::Config.max_redirects, 'Should respect RULEPACK_MAX_REDIRECTS env var'
  ensure
    ENV.delete('RULEPACK_MAX_REDIRECTS')
  end

  def test_fetch_url_respects_read_timeout_config
    timeout = Rulepack::Config.read_timeout
    assert_equal 30, timeout, 'Default read timeout should be 30 seconds'

    ENV['RULEPACK_READ_TIMEOUT'] = '60'
    assert_equal 60, Rulepack::Config.read_timeout, 'Should respect RULEPACK_READ_TIMEOUT env var'
  ensure
    ENV.delete('RULEPACK_READ_TIMEOUT')
  end

  def test_cached_fetch_handles_network_failure_gracefully
    TCPServer.new('127.0.0.1', 0) do |srv|
      port = srv.addr[1]
      srv.close

      assert_raises(RuntimeError) do
        Rulepack::Common.cached_fetch_url("http://127.0.0.1:#{port}/test", nil)
      end
    end
  end
end
