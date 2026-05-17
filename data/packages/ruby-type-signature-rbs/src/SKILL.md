---
name: generating-rbs
description: >
  Generates or updates RBS type signatures in separate .rbs files
  inside the sig/ directory. Triggers when creating, updating, or
  maintaining RBS type signatures for Ruby source files.
---

# Generating RBS Skill

Generate or update RBS type signatures in separate `.rbs` files. Supports both full generation from scratch and partial updates for individual changed files. Unlike RBS-inline, this skill places type information in dedicated `.rbs` files located in the `sig/` directory, keeping Ruby source files clean.

## Instructions

When generating RBS signatures, always follow these steps.

Copy this checklist and track your progress:

```
RBS Generation Progress:
- [ ] Step 1: Analyze the Ruby source
- [ ] Step 2: Add RBS annotations
- [ ] Step 3: Eliminate `untyped` types in annotations
- [ ] Step 4: Review and refine annotations
- [ ] Step 5: Validate annotations
- [ ] Step 6: Ensure type safety (only if steep is configured)
```

## Rules

- You MUST NOT run Ruby code of the project.
- You MUST NOT use `untyped`. Infer the proper type instead.
- You MUST ask the user to provide more details if something is not clear.
- You MUST prepend any command with `bundle exec` if the project has Gemfile.
- You MUST NOT use inline RBS annotations (`# @rbs` comments, `#:` shorthand).
- You MUST NOT use `sig/` prefix in type declarations.
- You MUST place RBS annotations in `.rbs` files under `sig/`.
- You MUST use the tracking file when processing multiple files to ensure no files are missed.

## Multi-File Processing

When processing multiple Ruby files, create a tracking file to ensure all files are covered:

1. **Create tracking file** `.rbs-generation-todo.tmp`:

```
[ ] app/models/user.rb
[ ] app/models/post.rb
[ ] app/services/auth_service.rb
```

2. **Process files one by one**:
   - Take the next pending `[ ]` entry
   - Complete all steps (1-6) for that file
   - Mark as processed `[x]`
   - Save the tracking file
   - Continue to next pending entry

3. **Cleanup**: Remove the tracking file after all files are processed:

```bash
rm .rbs-generation-todo.tmp
```

If interrupted, the tracking file allows resuming from where you left off.

## 1. Analyze the Ruby Source

Always perform this step.

Read and understand the Ruby source file:

- Identify all classes, modules, methods, constants and instance variables.
- Note inheritance, module inclusion and definitions based on metaprogramming.
- Note visibility modifiers — `public`, `private`, `protected`.
- Note type parameters for generic classes.

## 2. Add RBS Annotations

Always perform this step.

1. Determine the output `.rbs` file path under `sig/`, mirroring the Ruby source directory structure:

   - `lib/user.rb` → `sig/user.rbs`
   - `app/models/user.rb` → `sig/app/models/user.rbs`

2. Create or update the `.rbs` file with type declarations:

   **Example — Ruby source (`lib/user.rb`):**

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

   **Example — RBS signature (`sig/user.rbs`):**

   ```rbs
   class User
     attr_reader name: String
     attr_reader age: Integer

     def initialize: (String, Integer) -> void

     def greet: (String) -> String
   end
   ```

- Follow standard RBS syntax strictly.
- Pay extra attention to `Data` and `Struct` types.
- See `reference/data_and_struct.md` for Data and Struct handling.
- See `reference/rbs_by_example.md` for real-world RBS examples.

## 3. Eliminate `untyped` Types in Annotations

Always perform this step.

- Review all annotations and replace `untyped` with proper types.
- Use code context, method calls, and tests to infer types.
- Use `untyped` only as a last resort when type cannot be determined.

## 4. Review and Refine Annotations

Always perform this step.

- Verify annotations are correct, coherent, and complete.
- Remove unnecessary `untyped` types.
- Fix any errors and repeat until annotations are correct.

## 5. Validate Annotations

Always perform this step.

```bash
# Check RBS syntax and name resolution
rbs validate

# Or with bundle
bundle exec rbs validate
```

This checks syntax, name resolution, inheritance, and type applications.

Fix any errors in your `.rbs` files and repeat until validation passes.

## 6. Ensure Type Safety

Perform this step ONLY if the project Gemfile includes `steep` gem AND the project has Steepfile.

```bash
# Run Steep type checker
steep check

# Or with bundle
bundle exec steep check
```

Fix any errors reported by `steep check`.
- Do not modify Steepfile to fix errors.
- Fix the `.rbs` files and repeat until no errors.

## References

- `reference/data_and_struct.md` — Data and Struct handling in RBS
- `reference/rbs_by_example.md` — Real-world RBS examples from production gems
- [RBS documentation](https://github.com/ruby/rbs)
