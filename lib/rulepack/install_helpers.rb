# frozen_string_literal: true

# InstallHelpers — thin seam between Installer and Uninstaller.
# Exists to break the circular dependency: Uninstaller requires Common,
# and Common's facade delegates to InstallHelpers. Callers use
# Rulepack::Common.uninstall_packages without depending on Uninstaller directly.

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
