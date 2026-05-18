# frozen_string_literal: true

require 'set'

module Rulepack
  module TuiSelector
    module_function

    # Helper to read raw keyboard input, supporting arrow keys
    def read_keyboard_char
      require 'io/console'
      $stdin.echo = false
      $stdin.raw!
      input = $stdin.getc
      return '' unless input

      char = input.chr
      if char == "\e"
        begin
          char << $stdin.read_nonblock(2)
        rescue StandardError
          # Ignore non-blocking read errors
        end
      end
      char
    ensure
      $stdin.cooked!
      $stdin.echo = true
    end

    # Interactive sub-skill selection menu (pacman-style premium TUI)
    # Returns array of selected sub-skills, or nil to skip
    def prompt_sub_skill_selection(sub_skills, pkgname)
      return sub_skills unless $stdin.isatty && !ENV['RULEPACK_TEST']

      # Selected indices (0-indexed). Default: all selected.
      selected_indices = Set.new((0...sub_skills.size).to_a)
      cursor_index = 0

      # ANSI escape sequences
      cls_line = "\e[K"
      cursor_hide = "\e[?25l"
      cursor_show = "\e[?25h"

      puts "\n"
      puts "\e[38;5;99m┌──────────────────────────────────────────────────────────┐\e[0m"
      puts "\e[38;5;99m│\e[0m  \e[1mRulepack Interactive Selector:\e[0m \e[36m#{pkgname.to_s.ljust(25)}\e[0m \e[38;5;99m│\e[0m"
      puts "\e[38;5;99m└──────────────────────────────────────────────────────────┘\e[0m"
      puts "  \e[90mUse \e[37m[↑/↓] (or j/k)\e[90m to Navigate, \e[37m[Space]\e[90m to Toggle, \e[37m[Enter]\e[90m to Confirm\e[0m"
      puts "  \e[90mPress \e[37m[a]\e[90m for All, \e[37m[n]\e[90m for None, \e[37m[i]\e[90m to Invert, \e[37m[q]\e[90m to Quit\e[0m"
      puts ""

      # We will print sub_skills.size lines. Every update, we move the cursor up and reprint.
      lines_to_clear = sub_skills.size

      $stdout.write(cursor_hide)

      begin
        loop do
          # Print the list
          sub_skills.each_with_index do |ss, idx|
            is_cursor = (idx == cursor_index)
            is_selected = selected_indices.include?(idx)

            cursor_str = is_cursor ? "\e[38;5;220m▸\e[0m" : " "
            checkbox_str = is_selected ? "\e[38;5;46m⬢ [x]\e[0m" : "\e[38;5;240m⬡ [ ]\e[0m"
            
            name_str = ss['name']
            if is_cursor
              name_str = "\e[48;5;236m\e[1m\e[38;5;51m #{name_str} \e[0m"
            else
              name_str = "\e[37m#{name_str}\e[0m"
            end

            desc = ss['description'] || ss['path'] || ''
            desc_str = desc.empty? ? '' : " \e[90m— #{desc}\e[0m"

            puts "#{cursor_str} #{checkbox_str} #{name_str}#{desc_str}#{cls_line}"
          end

          # Read character
          char = read_keyboard_char

          case char
          when "\e[A", "k" # Up arrow or 'k'
            cursor_index = (cursor_index - 1) % sub_skills.size
          when "\e[B", "j" # Down arrow or 'j'
            cursor_index = (cursor_index + 1) % sub_skills.size
          when " " # Spacebar
            if selected_indices.include?(cursor_index)
              selected_indices.delete(cursor_index)
            else
              selected_indices.add(cursor_index)
            end
          when "a" # Select All
            selected_indices = Set.new((0...sub_skills.size).to_a)
          when "n" # Select None
            selected_indices.clear
          when "i" # Invert selection
            all_indices = Set.new((0...sub_skills.size).to_a)
            selected_indices = all_indices - selected_indices
          when "\r", "\n" # Enter
            break
          when "q", "\e", "\u0003" # Quit/ESC/Ctrl-C
            # Default to all if cancelled
            selected_indices = Set.new((0...sub_skills.size).to_a)
            break
          end

          # Move cursor back up
          $stdout.write("\e[#{lines_to_clear}A")
        end
      ensure
        $stdout.write(cursor_show)
      end

      selected = selected_indices.map { |i| sub_skills[i] }
      puts "\n  \e[32m✓ Selected #{selected.size} sub-skill(s) to install.\e[0m\n\n"
      selected
    end
  end
end
