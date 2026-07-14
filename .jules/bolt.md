## 2026-07-14 - Replace O(N) line-by-line array parsing with Ruby string-wide gsub!
**Learning:** For schema transformation on large chunks of text, splitting strings by `\n`, looping `O(N)` times applying `sub`, and `join`ing them later is terribly inefficient. Ruby's global `gsub!` operations done in C over a multi-line string with regex block processing is drastically faster.
**Action:** When doing bulk string replacement and formatting, use regexes (e.g. `gsub!(/^.../, ...)`) over the full string content directly rather than `.split("\n")` followed by `.map!` and `.join("\n")`.
