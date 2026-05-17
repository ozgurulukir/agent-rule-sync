---
name: generating-sorbet
description: >
  Generates or updates Sorbet RBI type signature files in separate .rbi files
  inside the sorbet/ or rbi/ directory. Triggers when creating, updating, or
  maintaining Sorbet type signatures for Ruby source files.
---

# Generating Sorbet Skill

Generate or update Sorbet type signatures in separate `.rbi` files. Supports both full generation from scratch and partial updates for individual changed files. Unlike Sorbet inline, this skill places type information in dedicated `.rbi` files, keeping Ruby source files clean.

## Instructions

When generating Sorbet RBI files, always follow these steps.

Copy this checklist and track your progress:

```
Sorbet RBI Generation Progress:
- [ ] Step 1: Analyze the Ruby source
- [ ] Step 2: Generate RBI file
- [ ] Step 3: Eliminate `T.untyped` in signatures
- [ ] Step 4: Review and refine signatures
- [ ] Step 5: Validate signatures with Sorbet
```

## Rules

- You MUST NOT run Ruby code of the project.
- You MUST NOT use `T.untyped`. Infer the proper type instead.
- You MUST NOT use `T.unsafe` — it bypasses type checking entirely.
- You MUST NOT use `T.cast` — it forces types without verification.
- You MUST ask the user to provide more details if something is not clear.
- You MUST prepend any command with `bundle exec` if the project has Gemfile.
- You MUST NOT use inline `sig {}` blocks in `.rb` files. This skill is for RBI files only.
- You MUST preserve the existing `# typed:` sigil level if one exists. Do not upgrade or change strictness without explicit user consent.
- You MUST use the tracking file when processing multiple files to ensure no files are missed.

## Multi-File Processing

When processing multiple Ruby files, create a tracking file to ensure all files are covered:

1. **Create tracking file** `.sorbet-generation-todo.tmp`:

```
[ ] app/models/user.rb
[ ] app/models/post.rb
[ ] app/services/auth_service.rb
```

2. **Process files one by one**:
   - Take the next pending `[ ]` entry
   - Complete all steps (1-5) for that file
   - Mark as processed `[x]`
   - Save the tracking file
   - Continue to next pending entry

3. **Cleanup**: Remove the tracking file after all files are processed:

```bash
rm .sorbet-generation-todo.tmp
```

If interrupted, the tracking file allows resuming from where you left off.

## 1. Analyze the Ruby Source

Always perform this step.

Read and understand the Ruby source file:

- Identify all classes, modules, methods, constants and instance variables.
- Note inheritance, module inclusion and definitions based on metaprogramming.
- Note visibility modifiers — `public`, `private`, `protected`.
- Note existing `# typed:` sigil level at the top of the file.
- Note type parameters for generic classes.

## 2. Generate RBI File

Always perform this step.

1. Determine the output `.rbi` file path, mirroring the Ruby source directory structure:

   - `lib/user.rb` → `sorbet/user.rbi`
   - `app/models/user.rb` → `sorbet/app/models/user.rbi`

2. Create or update the `.rbi` file with type declarations:

   **Example — Ruby source (`app/models/user.rb`):**

   ```ruby
   class User
     attr_reader :name, :age

     def initialize(name, age)
       @name = name
       @age = age
     end

     def greet(greeting)
       "#{greeting}, #{@name}!"
     end
   end
   ```

   **Example — RBI file (`sorbet/app/models/user.rbi`):**

   ```rbi
   # typed: true

   class User
     sig { returns(String) }
     attr_reader :name

     sig { returns(Integer) }
     attr_reader :age

     sig { params(name: String, age: Integer).void }
     def initialize(name, age); end

     sig { params(greeting: String).returns(String) }
     def greet(greeting); end
   end
   ```

- Follow standard RBI syntax.
- See `reference/syntax.md` for the full Sorbet RBI syntax guide.

## 3. Eliminate `T.untyped` in Signatures

Always perform this step.

- Review all signatures and replace `T.untyped` with proper types.
- Use code context, method calls, and tests to infer types.
- Use `T.untyped` only as a last resort when type cannot be determined.

## 4. Review and Refine Signatures

Always perform this step.

- Verify signatures are correct, coherent, and complete.
- Remove unnecessary `T.untyped` types.
- Ensure all methods and attributes have signatures.
- Fix any errors and repeat until signatures are correct.

## 5. Validate Signatures with Sorbet

Always perform this step.

Run Sorbet type checker to validate signatures:

```bash
srb tc
```

Or with bundle:

```bash
bundle exec srb tc
```

This checks:

- Signature syntax correctness
- Type consistency
- Method parameter/return type matching
- Instance variable initialization

Fix any errors reported and repeat until validation passes.

## References

- `reference/syntax.md` — Sorbet RBI syntax guide
- `reference/sorbet-examples.md` — Real-world Sorbet examples from production gems
- [Sorbet documentation](https://sorbet.org/docs/overview)
