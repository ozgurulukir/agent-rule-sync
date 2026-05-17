# Sorbet Examples — STRUCTURE.md

> **Note**: Full production examples are available in the upstream
> [`ruby-agent-skills`](https://github.com/DmitryPogrebnoy/ruby-agent-skills)
> repository under
> `plugins/ruby-type-signature-skills/skills/generating-sorbet/reference/rbs_by_example/`.

## Example Categories

| Category | File | Covers |
|---|---|---|
| Type aliases & unions | `type_aliases.rbi` | `T.type_alias`, `T.any`, `T.nilable` |
| Generics | `generics.rbi` | `T::Generic`, `type_member`, bounds |
| Interfaces | `interfaces.rbi` | `interface!`, `requires_ancestor` |
| Abstract classes | `abstract.rbi` | `abstract!`, `T::Helpers` |
| Enumerables & collections | `collections.rbi` | `T::Array`, `T::Hash`, `T::Set` |

## Conventions

- RBI files use `# typed: strict` at the top.
- All methods have explicit `sig {}` blocks — no bare method definitions.
- Use `; end` for method bodies in RBI files.
