# frozen_string_literal: true

module Rulepack
  # Unified loader for custom translators and transformers.
  #
  # Translators and transformers are loaded from `custom:<path>` strings declared
  # in PKGBUILD files. The loader:
  #
  #   1. Resolves the path relative to the repo root (or absolute/tilde paths).
  #   2. Validates the real path stays inside the repo (symlink attack defense).
  #   3. Loads the file with `load` so repeated builds pick up code changes.
  #   4. Returns the concrete processor module/class.
  #
  # Each processor file is expected to define a module named from its file basename
  # under `RulepackTranslator` (translators) or `RulepackTransformer` (transformers):
  #
  #   data/translators/rule_to_skill.rb  ->  RulepackTranslator::RuleToSkill
  #   data/transformers/add_frontmatter.rb -> RulepackTransformer::AddFrontmatter
  #
  # For backward compatibility the loader also accepts the legacy names
  # `RulepackTranslator::Impl`, `Translator`, `RulepackTransformer::Impl`, and `Transform`.
  module ProcessorLoader
    module_function

    def load_translator(spec)
      load_custom(spec, kind: :translator)
    end

    def load_transformer(spec)
      load_custom(spec, kind: :transformer)
    end

    def load_custom(spec, kind:)
      custom_path = resolve_path(spec)
      abs_path = validate_inside_repo(custom_path, kind).to_s

      load(abs_path)

      find_processor(abs_path, kind)
    end

    def resolve_path(spec)
      custom_rel = spec.to_s.sub(/\Acustom:/, '')
      path = if custom_rel.start_with?('/') || custom_rel.start_with?('~')
               Pathname.new(Rulepack::Common.expand_user_path(custom_rel))
             else
               Rulepack::Common::RULEPACK_ROOT.join(custom_rel)
             end
      path.cleanpath
    end

    def validate_inside_repo(custom_path, kind)
      unless custom_path.exist?
        raise "#{kind_label(kind)} not found: #{custom_path}. Verify the path in your PKGBUILD."
      end

      real_path = custom_path.realpath
      root = Rulepack::Common::RULEPACK_ROOT.realpath
      unless real_path.to_s.start_with?(root.to_s + File::SEPARATOR) || real_path == root
        raise "#{kind_label(kind)} path outside repo (symlink attack?): #{custom_path}"
      end
      real_path
    end

    def find_processor(abs_path, kind)
      module_name = module_name_from_path(abs_path)
      method_name = kind == :translator ? :translate : :transform

      candidates = case kind
                   when :translator
                     ["RulepackTranslator::#{module_name}", 'RulepackTranslator::Impl', 'Translator']
                   when :transformer
                     ["RulepackTransformer::#{module_name}", 'RulepackTransformer::Impl', 'Transform']
                   else
                     raise ArgumentError, "Unknown processor kind: #{kind}"
                   end

      candidates.each do |candidate|
        mod = resolve_const(candidate)
        next unless mod.respond_to?(method_name)

        return mod
      end

      raise "#{kind_label(kind)} #{abs_path} must define one of: #{candidates.join(', ')} " \
            "with a .#{method_name} class/module method"
    end

    def module_name_from_path(abs_path)
      File.basename(abs_path, '.rb').split('_').map(&:capitalize).join
    end

    def resolve_const(name)
      Object.const_get(name)
    rescue NameError
      nil
    end

    def kind_label(kind)
      kind.to_s.capitalize
    end
  end
end
