## 2026-07-14 - Replace O(N) line-by-line array parsing with Ruby string-wide gsub!
**Learning:** For schema transformation on large chunks of text, splitting strings by `\n`, looping `O(N)` times applying `sub`, and `join`ing them later is terribly inefficient. Ruby's global `gsub!` operations done in C over a multi-line string with regex block processing is drastically faster.
**Action:** When doing bulk string replacement and formatting, use regexes (e.g. `gsub!(/^.../, ...)`) over the full string content directly rather than `.split("\n")` followed by `.map!` and `.join("\n")`.
## 2026-07-14 - Optimizing Dependency Validation Lookups
**Learning:** `Rulepack::Common.validate_dependencies` in `lib/rulepack/build_loader.rb` performs nested loops over package index structures and executes `Array#include?` repeatedly, creating an O(N) bottleneck.
**Action:** Replace `Array#include?` with `Set#include?` for O(1) lookups and pre-compute `.to_s` conversions to prevent redundant string allocations during iterations, yielding ~100x speedup for large datasets.
