# CLI Tool Review Module

> Loaded when project matches: Node.js CLI (commander, yargs, oclif), Python CLI (click, argparse, typer), Go CLI (cobra), Rust CLI (clap)

## Detection Heuristics

Activate this module when any of the following are found:
- `package.json` with `bin` field, or dependencies: `commander`, `yargs`, `oclif`, `inquirer`, `chalk`, `ora`
- `pyproject.toml` with `[project.scripts]` or `[tool.poetry.scripts]`, or dependencies: `click`, `typer`, `rich`, `argparse`
- `go.mod` with `github.com/spf13/cobra`, `github.com/urfave/cli`
- `Cargo.toml` with `clap`, `structopt`, `dialoguer`
- Presence of `bin/`, `cli.js`, `cli.ts`, `__main__.py`, `cmd/` directory
- Shebang lines: `#!/usr/bin/env node`, `#!/usr/bin/env python3`
- Files named `main.go` in `cmd/` subdirectories (Go CLI pattern)

---

## Argument Handling

| Check | Severity | Description |
|-------|----------|-------------|
| No input validation on file paths | CRITICAL | File path argument used directly without resolving, validating existence, or checking traversal |
| Command injection via shell arguments | CRITICAL | User input passed to `child_process.exec`, `os.system`, `subprocess.Popen(shell=True)` |
| Missing required argument errors | HIGH | Tool crashes with stack trace instead of helpful error when required arg is missing |
| No type validation on arguments | MEDIUM | Numeric arguments not parsed/validated; string "abc" passed where number expected |
| Unconstrained glob expansion | HIGH | Glob pattern from user input expands to thousands of files with no limit |
| Conflicting arguments not detected | MEDIUM | Mutually exclusive options used together without error (e.g., `--json` and `--table`) |

### Detection patterns:
- `child_process.exec(` or `execSync(` with template literal or concatenated user input
- Python: `os.system(f"command {user_input}")` or `subprocess.run(cmd, shell=True)` with user input
- Go: `exec.Command("sh", "-c", userInput)`
- File path from args used in `fs.readFileSync(args.file)` without `path.resolve` + existence check
- Missing `.choices()`, `.number()`, or custom validation on argument definitions

### Safe subprocess patterns:
```javascript
// UNSAFE: shell injection
execSync(`grep ${pattern} ${file}`);
// SAFE: no shell, arguments as array
execFileSync('grep', [pattern, file]);
```
```python
# UNSAFE: shell injection
os.system(f"grep {pattern} {file}")
# SAFE: no shell, arguments as list
subprocess.run(["grep", pattern, file], check=True)
```

---

## Output

| Check | Severity | Description |
|-------|----------|-------------|
| Errors written to stdout | HIGH | Error messages mixed with normal output; breaks piping and parsing |
| No structured output option | MEDIUM | Missing `--json` or `--format` flag; output is only human-readable, not parseable |
| No exit codes for different failures | MEDIUM | Tool returns 1 for all errors; different failures should have distinct exit codes |
| Color output in non-TTY | MEDIUM | ANSI colors emitted when output is piped to file or another command |
| Verbose output by default | LOW | Tool dumps debug information without `--verbose` flag; noisy for scripting |
| Inconsistent output format | MEDIUM | Some commands output JSON, others output table, others output plain text; no consistency |

### Detection patterns:
- `console.log` used for errors (should be `console.error` or `process.stderr.write`)
- Python: `print()` for errors (should be `print(..., file=sys.stderr)` or `logging.error`)
- No `--json` or `--output` flag in argument definitions
- `process.exit(1)` or `sys.exit(1)` everywhere; no distinction between error types
- Missing `chalk.level = 0` or `NO_COLOR` / `FORCE_COLOR` environment variable support

### Exit code conventions:
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid usage / bad arguments |
| 126 | Permission denied |
| 127 | Command not found (when wrapping other tools) |
| 130 | Interrupted (SIGINT / Ctrl+C) |

---

## File System Operations

| Check | Severity | Description |
|-------|----------|-------------|
| Non-atomic file writes | HIGH | Writing directly to destination; crash during write = corrupted file. Use temp+rename pattern. |
| Missing permission handling | HIGH | `EACCES` / permission errors crash with stack trace instead of helpful message |
| Symlink following without check | MEDIUM | Operating on symlink target without verifying it's expected; symlink attack potential |
| Path resolution inconsistency | MEDIUM | Relative paths resolved differently based on cwd; use `path.resolve` consistently |
| No disk space check | MEDIUM | Large file operations without checking available space; fails mid-operation |
| Not cleaning up temp files | HIGH | Temporary files created but not cleaned up on error; orphaned temp files accumulate |

### Safe file write pattern:
```javascript
// Atomic write: write to temp, then rename
const tempPath = `${destPath}.tmp.${process.pid}`;
try {
  fs.writeFileSync(tempPath, content);
  fs.renameSync(tempPath, destPath); // atomic on same filesystem
} catch (err) {
  try { fs.unlinkSync(tempPath); } catch {}
  throw err;
}
```

---

## Configuration

| Check | Severity | Description |
|-------|----------|-------------|
| No config file validation | HIGH | Config file loaded and trusted without schema validation; malformed config causes cryptic errors |
| Wrong precedence order | MEDIUM | CLI args should override env vars, env vars override config file, config file overrides defaults |
| Config stored in project root | LOW | Config in project root but not in `.gitignore`; user-specific config committed |
| No default config generation | LOW | Missing `init` or `config` command to create default config file |
| Sensitive values in config file | HIGH | API keys or tokens stored in plaintext config; should use system keychain or env vars |
| XDG non-compliance | LOW | Config stored in home directory root instead of `~/.config/<tool>/` (Linux) or proper OS paths |

### Precedence (standard, verify this order):
1. CLI arguments (highest priority)
2. Environment variables
3. Project-level config (`.toolrc`, `tool.config.js` in cwd)
4. User-level config (`~/.config/tool/config.json`)
5. System defaults (lowest priority)

### Detection patterns:
- Config loaded from single source without merge/override logic
- `fs.readFileSync` of config file without try-catch or validation
- Hardcoded `~/.toolrc` path (not XDG compliant)
- No documentation of config file format or location

---

## Shell Interaction

| Check | Severity | Description |
|-------|----------|-------------|
| No TTY detection | HIGH | Interactive prompts sent when stdin is a pipe; breaks scripting (`echo "y" | tool` hangs) |
| Missing `--no-color` support | MEDIUM | No way to disable color output; breaks parsing and accessibility |
| No signal handling | HIGH | Ctrl+C doesn't clean up temp files, release locks, or restore terminal state |
| Interactive prompt in CI | HIGH | Prompt blocks in CI/CD pipeline; should detect non-interactive and fail with message |
| Missing `--yes` / `--force` flag | MEDIUM | Destructive operations always prompt; no way to automate confirmation |
| Terminal width assumption | LOW | Output formatted for 80 columns; wraps badly on narrow terminals or wide ones waste space |

### Detection patterns:
- `inquirer.prompt()` or `readline.question()` without checking `process.stdin.isTTY`
- Python: `input()` without checking `sys.stdin.isatty()`
- No `SIGINT` / `SIGTERM` handler: `process.on('SIGINT',` or `signal.signal(signal.SIGINT,` missing
- No `NO_COLOR` env var check (see https://no-color.org/)
- Chalk/colors used without conditional: should respect `--no-color` flag and `NO_COLOR` env

### Signal handling pattern:
```javascript
let cleanupDone = false;
function cleanup() {
  if (cleanupDone) return;
  cleanupDone = true;
  // Remove temp files, release locks, restore terminal
}
process.on('SIGINT', () => { cleanup(); process.exit(130); });
process.on('SIGTERM', () => { cleanup(); process.exit(143); });
process.on('exit', cleanup);
```

---

## Package Distribution

| Check | Severity | Description |
|-------|----------|-------------|
| Missing `bin` field | CRITICAL | `package.json` has no `bin` field; `npm install -g` won't create command |
| Missing shebang | HIGH | Entry file missing `#!/usr/bin/env node` (Node) or `#!/usr/bin/env python3` (Python) |
| Missing executable permission | HIGH | Entry file not `chmod +x`; fails on Unix when installed from tarball |
| Windows path handling | HIGH | Hardcoded `/` separators or Unix-specific paths; breaks on Windows |
| Missing `engines` field | MEDIUM | No minimum Node/Python version specified; fails cryptically on old versions |
| Large package size | MEDIUM | Publishing `node_modules`, test files, or build artifacts; check `files` field or `.npmignore` |

### Detection patterns:
- `package.json` missing `"bin": { "tool-name": "./cli.js" }`
- First line of entry file is not shebang
- `path.join` not used; paths constructed with string concatenation and `/`
- `os.path.join` not used in Python; hardcoded forward slashes
- Go: `filepath.Join` not used; `path.Join` used (wrong package for OS paths)
- Missing `"files"` field in `package.json`; publishes everything including tests

---

## Security

| Check | Severity | Description |
|-------|----------|-------------|
| `eval()` with user input | CRITICAL | User input evaluated as code; arbitrary code execution |
| `shell: true` with user arguments | CRITICAL | `child_process.spawn/exec` with `shell: true` and user-controlled args; command injection |
| Credentials logged | HIGH | API keys, tokens, passwords printed to stdout/stderr in debug/verbose mode |
| Credentials in command history | HIGH | Tool asks user to pass secret as CLI argument; visible in shell history |
| Insecure temp file creation | MEDIUM | Predictable temp file names; race condition for symlink attacks |
| No credential storage guidance | MEDIUM | Tool requires API key but no guidance on secure storage; users hardcode in scripts |

### Detection patterns:
- `eval(`, `new Function(`, `vm.runInNewContext(` with user-derived input
- `child_process.spawn(cmd, args, { shell: true })` where args contain user input
- `console.log` or `print` statements that output variables named `token`, `key`, `secret`, `password`
- Argument named `--api-key` or `--token` (visible in process list and shell history; prefer env var or file)

### Secure credential handling:
- Accept via environment variable: `process.env.TOOL_API_KEY`
- Accept via file: `--config ~/.tool/credentials` (with restricted permissions)
- Integrate with system keychain: `keytar` (Node), `keyring` (Python)
- Never log credential values even in debug mode; log `"API key: [REDACTED]"` instead

---

## Common AI Slop

| Pattern | Severity | What to look for |
|---------|----------|------------------|
| Hardcoded paths | HIGH | `/Users/username/project/` or `C:\Users\...` in source code; not portable |
| Missing error messages | HIGH | `process.exit(1)` or `sys.exit(1)` without any message explaining what went wrong |
| Sync file ops where async needed | MEDIUM | `fs.readFileSync` in a loop processing thousands of files; blocks event loop |
| `process.exit()` without cleanup | HIGH | `process.exit(0)` scattered throughout code; skips cleanup, doesn't flush streams |
| Missing `--help` / `--version` | MEDIUM | Basic CLI conventions missing; commander/yargs auto-generate these but custom tools forget |
| Hardcoded default values | MEDIUM | Magic numbers and strings in command logic instead of named constants or config |
| Error message says "Something went wrong" | HIGH | Generic error with no actionable information; user can't diagnose the problem |
| `console.log(JSON.stringify(data, null, 2))` everywhere | MEDIUM | Debugging output left in production code; or used as primary output without `--json` flag |
| Missing subcommand handling | MEDIUM | Unknown subcommand silently does nothing instead of showing help or error |
| No progress indication | MEDIUM | Long-running operations give no feedback; user thinks tool is hung |

---

## Testing Requirements

| Requirement | Priority | Details |
|-------------|----------|---------|
| Argument parsing tests | REQUIRED | Valid args, invalid args, missing required args, conflicting args |
| Error case tests | REQUIRED | Invalid input, missing files, permission denied, network failure |
| Exit code tests | REQUIRED | Correct exit code for success, each error type, interrupted |
| Integration tests with file system | REQUIRED | Real file creation, modification, deletion; verify actual file contents |
| Piped input/output tests | RECOMMENDED | Tool works correctly when stdin is pipe, stdout is pipe |
| Cross-platform tests | RECOMMENDED | Paths, line endings, permissions work on Linux, macOS, Windows |
| Signal handling tests | RECOMMENDED | SIGINT during operation cleans up properly |
| Help text tests | REQUIRED | `--help` produces useful output; no crashes on `--help` |

### Testing tools by ecosystem:
- **Node.js**: `execa` for subprocess testing, `memfs` for file system mocking, `jest` / `vitest`
- **Python**: `click.testing.CliRunner`, `pytest` with `tmp_path` fixture, `subprocess.run` for integration
- **Go**: `os/exec` in tests, `testing` package, `testify` for assertions
- **Rust**: `assert_cmd` crate, `predicates` crate, `tempfile` crate
