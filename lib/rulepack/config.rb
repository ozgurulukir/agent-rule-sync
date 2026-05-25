# frozen_string_literal: true

module Rulepack
  module Config
    module_function

    def max_redirects
      Integer(ENV.fetch('RULEPACK_MAX_REDIRECTS', '3'))
    end

    def read_timeout
      Integer(ENV.fetch('RULEPACK_READ_TIMEOUT', '30'))
    end

    def cache_dir_name
      ENV.fetch('RULEPACK_CACHE_DIR', 'cache')
    end

    def git_clone_depth
      Integer(ENV.fetch('RULEPACK_GIT_DEPTH', '1'))
    end

    # Maximum allowed size of the cache directory in megabytes.
    # Set RULEPACK_CACHE_MAX_MB=0 to disable the limit.
    def cache_max_size_mb
      Integer(ENV.fetch('RULEPACK_CACHE_MAX_MB', '500'))
    end

    def log_level
      ENV.fetch('RULEPACK_LOG_LEVEL', 'info').to_sym
    end
  end
end
