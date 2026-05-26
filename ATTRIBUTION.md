# Attribution

This document lists every package included in the Rulepack SSOT, its origin, and its
license. All packages are bundled as either Rulepack-authored rules, skills aggregated from
community projects, or standalone agent definitions.

---

## Package Manifest

### Community packages — upstream maintained

| Package | Origin | License |
|---|---|---|
| [antigravity-skills](https://github.com/rmyndharis/antigravity-skills) | rmyndharis/antigravity-skills | MIT |
| [cc-skills-golang](https://github.com/samber/cc-skills-golang) | samber/cc-skills-golang | MIT |
| [ruby-agent-skills](https://github.com/DmitryPogrebnoy/ruby-agent-skills) | DmitryPogrebnoy/ruby-agent-skills | MIT |
| [ruby-update-signatures](https://github.com/DmitryPogrebnoy/ruby-agent-skills) | DmitryPogrebnoy/ruby-agent-skills | MIT |
| [vibe-security](https://github.com/raroque/vibe-security-skill) | raroque/vibe-security-skill | MIT |

### Community packages — sourced from continuedev/awesome-rules

Skills in this group were adapted from
[continuedev/awesome-rules](https://github.com/continuedev/awesome-rules) and are
maintained in the Rulepack SSOT as local packages (`type: local` in their PKGBUILD).

| Package | Origin | License |
|---|---|---|
| [code-comments](https://github.com/continuedev/awesome-rules) | continuedev/awesome-rules | MIT |
| [error-handling](https://github.com/continuedev/awesome-rules) | continuedev/awesome-rules | MIT |
| [general-coding-standards](https://github.com/continuedev/awesome-rules) | continuedev/awesome-rules | MIT |
| [performance-optimization](https://github.com/continuedev/awesome-rules) | continuedev/awesome-rules | MIT |
| [readme-standards](https://github.com/continuedev/awesome-rules) | continuedev/awesome-rules | MIT |
| [task-management](https://github.com/continuedev/awesome-rules) | continuedev/awesome-rules | MIT |

### Rulepack SSOT — authored in this repository

Packages authored specifically for the Rulepack project and maintained under the
[`data/packages/`](data/packages/) tree.

| Package | Origin | License |
|---|---|---|
| [ast-grep](data/packages/ast-grep/PKGBUILD) | Rulepack SSOT | MIT |
| [code-reviewer](data/packages/code-reviewer/PKGBUILD) | Rulepack SSOT | MIT |
| [line-repetition-control](data/packages/line-repetition-control/PKGBUILD) | Rulepack SSOT | MIT |
| [memory](data/packages/memory/PKGBUILD) | Rulepack SSOT | MIT |
| [security-auditor](data/packages/security-auditor/PKGBUILD) | Rulepack SSOT | MIT |
| [shell](data/packages/shell/PKGBUILD) | Rulepack SSOT | MIT |
| [workstation-rules](data/packages/workstation-rules/PKGBUILD) | Rulepack SSOT | MIT |

---

## License Summary

All packages in this repository are licensed under the **MIT License** (18/18 packages).
Individual source files inherit their upstream license. Where an upstream license differs
from MIT, that license governs the relevant package contents.

---

*Generated automatically from `data/packages/*/PKGBUILD` maintainer and source fields.  
Last synced from `data/packages/` — 18 packages.*
