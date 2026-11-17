# Lua Code Checker

Lua Code Checker is a lightweight static-analysis tool written in Lua. It tokenizes source files and applies a focused set of rules for common reliability and maintainability risks. It is designed to run with a Lua interpreter and does not require a third-party parser package.

## Checks

| Rule | Purpose |
|---|---|
| `unchecked-io-open` | Finds file-handle use that does not adequately check whether `io.open` succeeded, including chained calls |
| `io-popen-usage` | Flags calls that start external processes |
| `blocking-loop-no-wait` | Finds loops that may run without yielding and are not statically bounded |
| `unverified-require` | Flags imports outside the known-present standard-library set |

These rules are deliberately narrow. The checker is a pattern-based analyzer, not a complete Lua parser, proof system, or guarantee that a program is safe.

## Usage

Analyze one or more files:

```bash
lua lua_code_checker.lua path/to/script.lua
lua lua_code_checker.lua first.lua second.lua
```

Write a modified copy:

```bash
lua lua_code_checker.lua --fix path/to/script.lua
```

The fixer writes a separate `.fixed.lua` file and leaves the original untouched.

## Conservative automatic repair

Only a standalone `require("module")` call is currently eligible for automatic wrapping in a protected call. Other findings remain diagnostics. Adding waits to loops, changing process execution, or rewriting file I/O can change application behavior and requires context beyond a local pattern match.

## Implementation

The tokenizer is implemented in `tokenizer.lua`. Each check is isolated in its own module under `rules/`, while `autofix.lua` contains the supported transformation. The command-line entry point coordinates file loading, analysis, reporting, and optional fixed-copy output.

The blocking-loop rule was refined against a source corpus to reduce false positives from ordinary bounded iteration. It still cannot reliably reason about every loop whose termination depends on side effects or function calls.

## Included fixture

Run the included sample with:

```bash
lua lua_code_checker.lua tests/sample_bad.lua
```

The README supplied with this project records an expected result of three errors and two warnings for that fixture. The repository does not currently include an automated test runner that executes the entire comparison corpus, so treat that historical comparison as a development note rather than a continuously enforced CI result.

## Project layout

```text
lua_code_checker.lua
tokenizer.lua
autofix.lua
rules/
  blocking_loop_no_wait.lua
  io_popen_usage.lua
  unchecked_io_open.lua
  unverified_require.lua
tests/
  sample_bad.lua
```

## Requirements and limitations

- Lua 5.1–5.4
- No external Lua dependencies for the checker itself

Because analysis is tokenizer- and pattern-based, dynamic code generation, unusual syntax, complex control flow, and project-specific module resolution may produce missed findings or false positives. Review every diagnostic and every generated fixed copy before using it.
