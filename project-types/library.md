# Library/Package Review Module

> Loaded when project matches: npm packages, PyPI packages, crates, Go modules, gems

## Detection Heuristics

Activate this module when any of the following are found:
- `package.json` without `private: true` AND with `main`, `module`, or `exports` fields
- `pyproject.toml` with `[build-system]` and `[project]` sections (not just a tool config)
- `setup.py` or `setup.cfg` with package metadata
- `Cargo.toml` with `[package]` section and `publish` not set to `false`
- `go.mod` defining a module with exported packages (no `cmd/` main pattern)
- `.gemspec` file present
- Presence of `dist/`, `lib/`, or `build/` in build scripts; `prepublish` or `prepack` scripts
- AND: project is not an application (no `bin` field, no `start` script suggesting an app)

---

## API Surface

| Check | Severity | Description |
|-------|----------|-------------|
| Unclear or missing exports | HIGH | No explicit `exports` field in package.json; or `main` points to wrong file |
| Missing TypeScript types | HIGH | JS library without `types`/`typings` field, no `.d.ts` files, no `@types` package |
| No JSDoc/docstrings on exports | MEDIUM | Public functions/classes exported without documentation |
| Internal modules exported | HIGH | Implementation details accessible via imports; no clear public vs internal separation |
| Default export issues | MEDIUM | Default export prevents tree-shaking and named import autocompletion |
| Inconsistent naming conventions | LOW | Mix of camelCase and snake_case in public API; or inconsistent verb/noun patterns |

### Detection patterns:
- `package.json` `exports` field missing or misconfigured (missing `.` entry, missing `types` condition)
- `index.ts` re-exports with `export *` from implementation files (exposes everything)
- Functions in exported modules missing JSDoc `@param`, `@returns` annotations
- TypeScript: exported types missing; consumers would need `typeof import(...)` hacks
- Python: `__all__` not defined in `__init__.py`; all module internals importable

### Proper exports configuration:
```json
{
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.mjs",
      "require": "./dist/index.cjs"
    },
    "./utils": {
      "types": "./dist/utils.d.ts",
      "import": "./dist/utils.mjs",
      "require": "./dist/utils.cjs"
    }
  }
}
```

---

## Breaking Changes

| Check | Severity | Description |
|-------|----------|-------------|
| Removed export without major bump | CRITICAL | Previously exported function/class/type removed; consumers will break on update |
| Changed function signature | CRITICAL | Required parameters added, parameter types narrowed, return type changed |
| Changed default behavior | HIGH | Default options changed; existing code produces different results without code changes |
| Renamed export | CRITICAL | Named export renamed without alias; `import { oldName }` breaks |
| Narrowed type | HIGH | TypeScript type that accepted `string | number` now only accepts `string` |
| Changed error behavior | MEDIUM | Function that returned `null` now throws; or vice versa |
| Minimum runtime version bump | MEDIUM | `engines` field increased; consumers on older versions break |

### Detection approach:
- Compare current exports against previous published version
- Check `CHANGELOG.md` or `HISTORY.md` for documented breaks
- Verify version bump matches semver: breaking changes require major bump
- Look for TODO/FIXME comments mentioning deprecation or removal

---

## Bundle Impact

| Check | Severity | Description |
|-------|----------|-------------|
| Not tree-shakeable | HIGH | CommonJS-only output; or ESM output with side effects that prevent dead code elimination |
| Missing `sideEffects` field | MEDIUM | `package.json` lacks `sideEffects: false`; bundlers cannot safely tree-shake |
| Unnecessary dependencies | HIGH | Runtime dependencies used for trivial tasks (is-odd, left-pad, etc.) |
| Heavy dependencies | HIGH | Pulling in large dependency for small feature; `lodash` for one function, `moment` for date formatting |
| CSS bundled with JS | MEDIUM | Styles imported in JS without option to import separately; forces all consumers to handle CSS |
| Polyfills included unconditionally | MEDIUM | Polyfills bundled that most target environments don't need |

### Detection patterns:
- Only `.cjs` or `require()` output; no `.mjs` or ESM build
- `package.json` missing `"sideEffects": false` or `"sideEffects": ["*.css"]`
- `dependencies` in package.json that are only used in tests or build (should be `devDependencies`)
- `node_modules` included in published package (check `files` field or `.npmignore`)
- Single dependency that adds >100KB to consumer bundle

### Dependency audit checklist:
```
[ ] Every dependency in "dependencies" is actually imported in published source
[ ] No dependency duplicates functionality available in the language standard library
[ ] No dependency is imported for a single trivial function (inline it instead)
[ ] Dev-only dependencies are in "devDependencies"
[ ] Peer dependencies have correct version ranges
```

---

## Peer Dependencies

| Check | Severity | Description |
|-------|----------|-------------|
| Missing peer dependency declaration | HIGH | Library imports `react` at runtime but doesn't declare it as peer dependency |
| Peer dependency in `dependencies` | HIGH | Framework listed in `dependencies` instead of `peerDependencies`; duplicated in consumer bundle |
| Overly narrow peer range | MEDIUM | `"react": "18.2.0"` instead of `"react": "^18.0.0"`; breaks with minor updates |
| Overly broad peer range | MEDIUM | `"react": ">=16"` claims compatibility across 3 major versions without testing |
| Missing `peerDependenciesMeta` | LOW | Optional peer dependency not marked as optional; install warns unnecessarily |

### Detection patterns:
- `import React from 'react'` in source, but `react` is in `dependencies` not `peerDependencies`
- Peer dependency version range includes versions that the library has never been tested against
- Python equivalent: library imports `django` but doesn't declare minimum version in `install_requires`

---

## Security Surface

| Check | Severity | Description |
|-------|----------|-------------|
| `eval()` in library code | CRITICAL | Library evaluates strings as code; consumers inherit RCE vulnerability |
| Dynamic `require`/`import` with user input | CRITICAL | `require(userProvidedPath)` enables arbitrary module loading |
| Prototype pollution | CRITICAL | Deep merge/extend functions that copy `__proto__`, `constructor`, `prototype` properties |
| Regular expression DoS (ReDoS) | HIGH | Regex with nested quantifiers or overlapping alternatives; catastrophic backtracking on crafted input |
| Unsafe defaults | HIGH | Library defaults to insecure options (e.g., disabled validation, permissive parsing) |
| Environment variable access | MEDIUM | Library reads environment variables without documenting which ones and why |

### Detection patterns:
- `eval(`, `new Function(`, `vm.runInNewContext(` with any parameter that could originate from consumer input
- `require(variable)` or `import(variable)` where variable is not a hardcoded string
- Object merge functions: check if they skip `__proto__` and `constructor` keys
- Regex patterns: look for `(a+)+`, `(a|a)+`, `(a|b)*c` patterns that cause backtracking
- Python: `pickle.loads(user_input)`, `yaml.load(data)` without `Loader=SafeLoader`

### Prototype pollution safe merge:
```javascript
function safeMerge(target, source) {
  for (const key of Object.keys(source)) {
    if (key === '__proto__' || key === 'constructor' || key === 'prototype') continue;
    // ... merge logic
  }
}
```

---

## Testing

| Check | Severity | Description |
|-------|----------|-------------|
| No tests for public API | CRITICAL | Exported functions/classes have no test coverage |
| Tests only cover happy path | HIGH | No edge cases: empty input, null, undefined, wrong types, boundary values |
| Missing compatibility tests | MEDIUM | Library claims to support Node 16-20 but tests only run on one version |
| Tests use implementation details | MEDIUM | Tests import internal modules; will break on refactor even if public API unchanged |
| No integration tests | MEDIUM | Only unit tests with mocks; no test that exercises real integration |
| Missing type tests | MEDIUM | TypeScript types not tested; types could diverge from runtime behavior |

### Type testing patterns:
```typescript
// Use expectTypeOf (vitest) or tsd
import { expectTypeOf } from 'vitest';
import { parseConfig } from './index';

test('parseConfig returns Config type', () => {
  expectTypeOf(parseConfig).parameter(0).toMatchTypeOf<string>();
  expectTypeOf(parseConfig).returns.toMatchTypeOf<Config>();
});
```

---

## Documentation

| Check | Severity | Description |
|-------|----------|-------------|
| No README or empty README | HIGH | Package published without usage documentation |
| No API documentation | HIGH | Functions exported but no docs explaining parameters, return values, behavior |
| Missing usage examples | MEDIUM | Docs explain API but no practical examples showing common use cases |
| No migration guide for major version | HIGH | Major version bump without documentation of breaking changes and migration path |
| No changelog | MEDIUM | No CHANGELOG.md or GitHub releases; consumers can't understand what changed |
| Stale documentation | MEDIUM | Docs reference APIs or behavior that no longer exists |

---

## Package Metadata

| Check | Severity | Description |
|-------|----------|-------------|
| Wrong `main`/`module`/`exports` | CRITICAL | Entry point fields reference files that don't exist in published package |
| Missing `files` field | HIGH | No `files` field and no `.npmignore`; publishes tests, configs, CI files |
| Missing `license` field | HIGH | Package published without license; consumers can't legally use it |
| Missing `repository` field | LOW | No link to source code; consumers can't report bugs or contribute |
| Version not bumped | MEDIUM | Code changes without version increment; consumers won't get updates |
| Missing `engines` field | MEDIUM | No minimum runtime version declared; breaks silently on old Node/Python |

### Detection patterns:
- `package.json` `main` pointing to `src/index.ts` instead of `dist/index.js`
- `files` field missing; run `npm pack --dry-run` equivalent to see what would be published
- Python: `pyproject.toml` missing `[project.urls]`, `license`, `requires-python`
- `version` in package.json same as latest published version despite code changes

---

## Common AI Slop

| Pattern | Severity | What to look for |
|---------|----------|------------------|
| Default export breaking tree-shaking | HIGH | `export default { method1, method2 }` instead of named exports; consumers get entire object |
| Missing TypeScript declarations | HIGH | Library written in TS but `declaration: true` not in tsconfig; no `.d.ts` output |
| Overly broad dependency versions | HIGH | `"lodash": "*"` or `"axios": ">=0.1.0"` instead of pinned or caret range |
| Runtime deps that should be dev | HIGH | `jest`, `typescript`, `eslint`, `prettier` in `dependencies` instead of `devDependencies` |
| Barrel file exports everything | MEDIUM | `export * from './internal/module'` exposing internal implementation |
| Console.log left in library | HIGH | `console.log` or `console.warn` in published code; pollutes consumer output |
| Unnecessary `async` | MEDIUM | Functions marked `async` that contain no `await`; return implicit promise wrapper |
| Hardcoded configuration | MEDIUM | Magic values that should be consumer-configurable |
| Missing error types | MEDIUM | All errors thrown as generic `Error` instead of typed errors consumers can catch specifically |
| No input validation on public API | HIGH | Exported function accepts `any` and crashes on wrong input instead of validating and throwing helpful error |

---

## Publishing Readiness

### Pre-publish checklist:
```
[ ] Version bumped according to semver
[ ] CHANGELOG updated with version changes
[ ] "files" field in package.json lists only needed files (or .npmignore excludes test/config)
[ ] "main", "module", "exports", "types" fields point to correct built files
[ ] "license" field present and matches LICENSE file
[ ] "engines" field specifies minimum runtime version
[ ] "peerDependencies" declared for framework dependencies
[ ] "sideEffects" field set appropriately
[ ] Build output is correct: dist/ contains expected files
[ ] Tests pass against built output (not source)
[ ] No console.log/debug output in published code
[ ] No secrets, credentials, or internal URLs in published files
[ ] README has install instructions, basic usage, and API overview
[ ] npm pack --dry-run shows expected files only
[ ] Type declarations present and valid
[ ] prepublishOnly script runs build and tests
```

### `npm pack` audit:
Run `npm pack --dry-run` or equivalent and verify:
- No `tests/`, `__tests__/`, `*.test.*`, `*.spec.*` files included
- No `.env`, `.env.*` files included
- No `tsconfig.json`, `jest.config.*`, `.eslintrc.*` included
- No `.git/` directory included
- No `node_modules/` included
- Total package size is reasonable (<1MB for most libraries)
