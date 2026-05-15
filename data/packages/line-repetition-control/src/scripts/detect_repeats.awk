#!/usr/bin/awk -f

# detect_repeats.awk
# Usage: awk -f detect_repeats.awk <file>

BEGIN {
    # Heuristic Exception List
    exceptions[""] = 1; exceptions["{"] = 1; exceptions["}"] = 1;
    exceptions["["] = 1; exceptions["]"] = 1; exceptions["("] = 1;
    exceptions[")"] = 1; exceptions["else:"] = 1; exceptions["else"] = 1;
    exceptions["end"] = 1; exceptions["pass"] = 1; exceptions["continue"] = 1;
    exceptions["break"] = 1;
    exceptions["});"] = 1; exceptions["};"] = 1; exceptions["],"] = 1;
    exceptions["},"] = 1; exceptions[");"] = 1; exceptions["),"] = 1;

    # Pattern for separators (e.g., // ============)
    # Since mawk 1.3.4 doesn't support backreferences (\1, \2), we check for common
    # repeating characters (3+) explicitly after optional comment/space markers.
    sep_pattern = "^(/+|#|--|[ \t])*([=]{3,}|[-]{3,}|[*]{3,}|[_]{3,})[ \t]*$";
}

function is_ignorable(line) {
    if (line in exceptions || length(line) < 3) return 1;
    if (line ~ sep_pattern) return 1;
    return 0;
}

{
    # Clean whitespace for comparison
    line = $0;
    gsub(/^[ \t]+|[ \t]+$/, "", line);
    lines[NR] = line;
}

END {
    for (i = 1; i <= NR; i++) {
        current = lines[i];
        
        # Skip exceptions and short lines
        if (is_ignorable(current)) {
            continue;
        }

        # 1. Consecutive Line Detection
        count = 1;
        while (i + count <= NR && lines[i + count] == current) {
            count++;
        }

        if (count > 1) {
            printf "[Line %d] Repeated %dx: %s\n", i, count, current;
            i += (count - 1);
            continue;
        }

        # 2. Block Detection (2-5 lines)
        found_block = 0;
        for (size = 5; size >= 2; size--) {
            if (i + (size * 2) - 1 <= NR) {
                # Count consecutive repetitions of this block
                block_count = 1;
                while (1) {
                    match_found = 1;
                    if (i + (block_count + 1) * size - 1 > NR) {
                        match_found = 0;
                    } else {
                        for (k = 0; k < size; k++) {
                            if (lines[i + k] != lines[i + block_count * size + k]) {
                                match_found = 0;
                                break;
                            }
                        }
                    }
                    
                    if (match_found) {
                        block_count++;
                    } else {
                        break;
                    }
                }
                
                if (block_count > 1) {
                    # Check if block is not just exceptions
                    all_exceptions = 1;
                    for (k = 0; k < size; k++) {
                        if (!is_ignorable(lines[i + k])) {
                            all_exceptions = 0;
                            break;
                        }
                    }
                    
                    if (!all_exceptions) {
                        printf "[Line %d] Repeated Block (%d lines) %dx\n", i, size, block_count;
                        for (k = 0; k < size; k++) {
                            printf "  > %s\n", lines[i + k];
                        }
                        i += (size * block_count) - 1;
                        found_block = 1;
                        break;
                    }
                }
            }
        }
    }
}
