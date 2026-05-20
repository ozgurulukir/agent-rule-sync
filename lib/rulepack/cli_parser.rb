# frozen_string_literal: true

require 'pathname'

module Rulepack
  module CliParser
    module_function

    # Parses ARGV for verification and repair tools
    # Returns a Hash with symbolized options
    def parse(argv_array)
      args = argv_array.dup

      # Pacman flags shifting
      args.shift if %w[-S -R -Qk -F -Q].include?(args.first)

      options = {
        package_name: nil,
        target: nil,
        project_path: nil,
        dry_run: false,
        auto: false,
        force: false,
        needed: false,
        select: false,
        on_collision: nil,
        verbose: false,
        check_mode: false,
        targets_mode: false
      }

      positional = []
      i = 0
      while i < args.length
        arg = args[i]
        case arg
        when '--target', '-t'
          raise 'Missing value for --target' if i + 1 >= args.length
          options[:target] = args[i + 1]
          i += 2
        when '--project', '-p'
          raise 'Missing path for --project' if i + 1 >= args.length
          options[:project_path] = args[i + 1]
          i += 2
        when '--on-collision'
          raise 'Missing value for --on-collision' if i + 1 >= args.length
          val = args[i + 1].downcase
          unless %w[stop ignore overwrite append].include?(val)
            raise "Invalid collision strategy: #{val}. Valid: stop, ignore, overwrite, append"
          end
          options[:on_collision] = val
          i += 2
        when '--dry-run'
          options[:dry_run] = true
          i += 1
        when '--auto'
          options[:auto] = true
          i += 1
        when '--force', '-f'
          options[:force] = true
          i += 1
        when '--needed'
          options[:needed] = true
          i += 1
        when '--select'
          if i + 1 < args.length && !args[i + 1].start_with?('-')
            options[:select] = args[i + 1].split(',').map(&:strip).reject(&:empty?)
            i += 2
          else
            options[:select] = :interactive
            i += 1
          end
        when '--verbose', '-v'
          options[:verbose] = true
          i += 1
        when '--check'
          options[:check_mode] = true
          i += 1
        when '--targets'
          options[:targets_mode] = true
          i += 1
        else
          positional << arg
          i += 1
        end
      end

      if positional.size > 1
        options[:package_name] = positional.first
        # Keep any secondary positional arguments if needed
        options[:extra_positional] = positional[1..-1]
      else
        options[:package_name] = positional.first
      end

      options[:positional] = positional
      options
    end
  end
end
