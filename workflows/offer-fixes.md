# Fix Application Protocol

This workflow governs how the orchestrator applies fixes for findings produced by the Ultimate Code Review. It is invoked when the user accepts the offer to apply fixes, or requests fixes explicitly.

---

## 1. Fix Scope Selection

Before applying any fixes, the user selects a scope. Present exactly three options:

### Preset: "blockers"

Apply fixes only for findings where `blocks_release: yes`. This is the minimum set required to move toward release readiness.

### Preset: "critical-major"

Apply fixes for all findings at Critical or Major severity, regardless of whether they block release.

### Preset: "selected"

The user provides a list of specific finding IDs (e.g., `UCR-001, UCR-007, UCR-014`). Apply fixes only for those findings. Validate that every provided ID exists in the current review before proceeding. If any ID is not found, report it and ask the user to confirm before continuing with the valid subset.

### Scope confirmation

After the user selects a preset, display the list of findings that will be addressed:

```
Scope: {preset name}
Findings to fix ({count}):
  UCR-001: {title} [{severity}]
  UCR-003: {title} [{severity}]
  ...

Proceed? (yes / adjust selection)
```

Wait for explicit confirmation before applying any changes.

---

## 2. Conflict Resolution

When two or more fixes modify the same region of the same file, a conflict exists. Conflicts must be identified and resolved **before** any fixes in the conflicting set are applied.

### Detection

Before applying fixes within a group, collect the full set of files and line ranges each fix will touch. If any two fixes overlap in file and line range, flag the conflict.

### Resolution rules

Apply these rules in order:

1. **Higher severity wins.** If one fix addresses a Critical finding and the other addresses a Major finding, apply the Critical fix. Defer the Major fix.

2. **Wider scope wins (same severity).** If both fixes are the same severity, apply the fix that affects more code paths or more users. "Wider scope" means the fix that addresses a more systemic issue rather than a localized one.

3. **If still tied**, apply the fix for the finding with the lower UCR ID number (i.e., the one discovered first). This is arbitrary but deterministic.

### Deferral

The losing fix is **deferred**, not discarded. Deferral means:

- The fix is NOT applied automatically.
- The conflict is documented in full (see below).
- Manual resolution guidance is provided so the user can apply it by hand.

### Conflict documentation

For every conflict, record:

```
Conflict:
  Fix A: UCR-{id} — {title}
  Fix B: UCR-{id} — {title}
  Overlapping file(s): {path}:{line range}
  Applied: UCR-{id} (reason: {severity advantage | wider scope | earlier discovery})
  Deferred: UCR-{id}
  Manual resolution: {step-by-step guidance for applying the deferred fix after the applied fix}
```

---

## 3. Fix Grouping

Fixes are not applied one at a time. They are grouped into logical units so that each commit represents a coherent, reviewable change. Group by category:

| Group              | Contains fixes for                                                  |
| ------------------ | ------------------------------------------------------------------- |
| Security           | Authentication bypass, injection, secrets exposure, CSRF, XSS, etc.|
| Auth               | Authorization logic, role checks, permission enforcement            |
| Validation         | Input validation, schema enforcement, boundary checks               |
| Error Handling     | Missing error handling, swallowed exceptions, crash-on-failure      |
| Data Integrity     | Race conditions, data loss, inconsistent state                      |
| Performance        | Memory leaks, N+1 queries, unnecessary computation                  |
| UI/UX              | Layout, accessibility, user-facing text, interaction bugs           |
| Testing            | Missing tests, flawed assertions, test infrastructure               |
| Configuration      | Env handling, build config, deployment config                       |
| Code Quality       | Dead code, naming, duplication, readability                         |

### Grouping rules

- A fix belongs to the group matching its finding's primary category.
- If a fix spans two categories (e.g., a validation fix that also fixes a security issue), place it in the higher-severity category's group.
- If a group would contain only one fix, that is fine. Do not merge groups to reduce commit count.
- If a group would contain more than 15 fixes, split it into subgroups by file or subsystem (e.g., "Security: API routes", "Security: middleware").

### Group ordering

Apply groups in this order (highest risk first):

1. Security
2. Auth
3. Data Integrity
4. Validation
5. Error Handling
6. Performance
7. Configuration
8. Testing
9. UI/UX
10. Code Quality

---

## 4. Fix Application Per Group

For each fix group, execute the following steps in sequence. Do not proceed to the next group until the current group is fully resolved.

### Step A: Read all affected files

Read every file that will be modified by any fix in the current group. This ensures you have the current state of each file before making changes, and can detect if a file has been modified by a previous group.

### Step B: Apply fixes

Use the Edit tool to apply each fix in the group. Apply fixes within a group in order of severity (Critical first, then Major, then Moderate, then Minor). Within the same severity, apply in UCR ID order.

For each fix:

- Make the minimum change necessary to address the finding.
- Preserve existing code style, indentation, and conventions.
- Do not refactor surrounding code unless the fix requires it.
- Do not add comments like `// UCR fix` to the code. The commit message provides traceability.

### Step C: Run targeted validation

Immediately after applying all fixes in the group, validate:

1. **Tests**: If tests exist for the affected code, run them. Use the project's test runner (detected from package.json, Cargo.toml, pyproject.toml, Makefile, etc.). Run only the relevant test files or test suites, not the entire test suite.

2. **Type checker**: If the project uses a type checker (TypeScript `tsc`, Python `mypy`/`pyright`, etc.), run it on the affected files.

3. **Linter**: If the project uses a linter (ESLint, Ruff, Clippy, etc.), run it on the affected files.

4. **Semantic verification**: Confirm that the fix actually addresses the finding. Re-read the affected code and verify the vulnerability, bug, or issue described in the finding is no longer present.

### Step D: Handle validation failures

If any validation step fails:

- **Revert the fix** that caused the failure. Use the Edit tool to restore the original code (you read it in Step A).
- **Do not attempt to fix the fix.** Automated fix-on-fix chains compound risk.
- **Document the failure**:
  ```
  Failed fix: UCR-{id} — {title}
  Validation failure: {which step failed}
  Error: {error message or description}
  Why: {brief analysis of why the automated fix didn't work}
  Manual resolution: {what the developer should do instead}
  ```
- **Add to the "needs manual fix" list.** This list appears in the final summary.
- **Continue with the remaining fixes in the group.** One failure does not abort the group.

### Step E: Commit the fix group

After all fixes in the group are applied and validated (or reverted), create a single commit for the group.

Commit message format:

```
fix(ucr): {group description} [UCR-{comma-separated ids}]

Applied {count} automated fixes for {category} findings.

Findings addressed:
- UCR-{id}: {one-line title}
- UCR-{id}: {one-line title}
```

Rules:

- **One commit per logical fix group.** Never combine groups into a single commit.
- **NEVER amend existing commits.** Always create new commits.
- **Do not commit reverted fixes.** Only committed code should be working, validated fixes.
- If all fixes in a group were reverted (all failed validation), skip the commit for that group entirely.

---

## 5. Post-Fix Re-Review

After ALL fix groups have been applied (or attempted), run a scoped re-review.

### Re-review scope

- **Files**: Every file that was modified by any applied fix.
- **Findings**: Every finding that was marked `blocks_release: yes`, regardless of whether a fix was attempted.

### Re-review process

Spawn a focused review subagent (not a full UCR pass) that:

1. Reads all affected files in their current (post-fix) state.
2. Checks each applied fix: does the original finding still exist? Is the fix correct and complete?
3. Checks each `blocks_release` finding: is it resolved? If it was not in the fix scope, is it still present?
4. Scans for **new issues introduced by the fixes**: regressions, new bugs, new security issues, broken imports, type errors.

### Re-review output

```
Post-Fix Re-Review Results:
  Verified as resolved: {count}
    - UCR-{id}: {title} — confirmed fixed
    - ...
  Still present: {count}
    - UCR-{id}: {title} — {why it's still present}
    - ...
  New issues introduced: {count}
    - NEW-001: {description} in {file}:{line}
    - ...
```

If new issues are found, report them but do NOT attempt to fix them automatically. They require human review.

---

## 6. Fix Summary Output

After the re-review completes, produce the final fix summary. This is included in the review report and also displayed directly to the user.

```markdown
## Fix Summary

### Applied ({count})
| Finding | Title | Commit |
|---------|-------|--------|
| UCR-001 | {title} | `{short hash}` |
| UCR-003 | {title} | `{short hash}` |

### Deferred Due to Conflicts ({count})
| Finding | Conflicts With | Reason | Manual Steps |
|---------|---------------|--------|--------------|
| UCR-002 | UCR-001 | {explanation} | {steps} |

### Failed Validation ({count})
| Finding | Title | Failure Reason | Manual Steps |
|---------|-------|---------------|--------------|
| UCR-005 | {title} | {why} | {what to do} |

### Not Attempted ({count})
| Finding | Title | Reason |
|---------|-------|--------|
| UCR-010 | {title} | Outside selected scope |

### Post-Fix Re-Review
- **{count}** findings verified as resolved
- **{count}** findings still present
- **{count}** new issues introduced by fixes

### Updated Release Verdict
{If the fix application changed the release readiness, state the new verdict here.
 If blockers remain, state what still needs to be addressed.}
```

---

## Behavioral Rules

- **Never apply fixes without user confirmation of scope.**
- **Never amend commits.** Every fix group gets its own new commit.
- **Never attempt to fix a failed fix.** Revert and document.
- **Never skip validation.** If no test runner / linter / type checker is available, note that validation was limited to semantic verification only.
- **Never modify files outside the fix scope.** If a fix requires changes to files not related to the finding, defer it with an explanation.
- **Always read before editing.** Every file must be read before it is modified.
- **Always preserve the user's code style.** Match indentation, quotes, semicolons, naming conventions.
