# frozen_string_literal: true

# Thin helper over Common.apply_translator; translator resolution lives in Common.

def run_translator(translator_spec, content, pkgname: nil)
  Rulepack::Common.apply_translator(translator_spec, content, pkgname: pkgname)
end

