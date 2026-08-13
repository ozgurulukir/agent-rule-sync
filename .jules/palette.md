## 2026-07-13 - [CLI UX]
**Learning:** Add confirmation prompts before destructive actions. This improves user confidence and prevents accidental data loss. Using `tty-prompt` is generally better, but standard `$stdin.gets` works for minimal dependencies. Ensure tests (`ENV['RULEPACK_TEST']`) bypass prompts to not hang CI.
**Action:** Implemented a `y/N` confirmation prompt before uninstalling packages.

## 2026-07-17 - Graceful Fallback and Nested CLI Spinners
**Learning:** Adding a spinner to long operations requires handling nested contexts and CI degradations. If a spun operation calls another spun operation, they will fight for stdout cursor space resulting in mangled terminal text.
**Action:** When implementing CLI spinners, include checks for CI environments (`ENV['CI']`), non-TTY outputs (`!$stdout.isatty`), test modes (`ENV['RULEPACK_TEST']`), and use thread-local variables (`Thread.current[:in_spinner]`) to prevent nested spinners from overwriting each other.

## 2026-07-20 - Interactive Fallbacks
**Learning:** Command line tools should seamlessly guide users to completion instead of abruptly halting and asking them to re-run with a flag (like `--auto`). Asking "Remove orphans? [y/N]" at runtime directly solves the user's problem without making them retype the command.
**Action:** When a command requires a flag for a destructive or complex operation, implement an interactive fallback prompt for TTY sessions, ensuring `ENV['RULEPACK_TEST']` is respected.

## 2026-07-24 - Handle EOF in Interactive Fallbacks
**Learning:** Adding an interactive fallback prompt requires handling EOF correctly (e.g. when `gets` returns `nil` due to a `Ctrl+D` signal). Failing to do so in a `loop` reading `$stdin` leads to an infinite loop, maxing out CPU and breaking CI/TTY functionality.
**Action:** Whenever using `gets` in an interactive prompt loop, explicitly check for `input.nil?` and exit gracefully or provide a default fallback strategy instead of letting `.chomp.downcase` fail or loop endlessly.
