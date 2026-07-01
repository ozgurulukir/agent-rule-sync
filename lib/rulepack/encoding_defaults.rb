# frozen_string_literal: true

# Force UTF-8 as the default external encoding so that all File.read / Pathname#read
# calls return UTF-8 strings regardless of the process locale. This prevents
# "invalid byte sequence in US-ASCII" errors when processing markdown that contains
# non-ASCII characters (common in skill bundles and agent rules).

Encoding.default_external = Encoding::UTF_8
