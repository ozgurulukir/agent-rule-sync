# frozen_string_literal: true

module Rulepack
  module InstallHelpers
    module_function

    # Uninstall packages from a platform (thin wrapper around Uninstaller)
    def uninstall_packages(index, platform_id, dry_run: false, project_root: nil,
                           specific_packages: nil, ctx: nil)
      Rulepack::Uninstaller.uninstall_packages(index, platform_id,
                                                dry_run: dry_run,
                                                project_root: project_root,
                                                specific_packages: specific_packages,
                                                ctx: ctx)
    end

    # Migrate installed records in the index to add missing fields
    def migrate_installed_records(pkg_index)
      Rulepack::Uninstaller.migrate_installed_records(pkg_index)
    end
  end
end
