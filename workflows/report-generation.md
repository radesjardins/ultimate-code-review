# Report Generation Protocol

This workflow governs how the orchestrator assembles, masks, and writes the final Ultimate Code Review report. It is invoked after all review phases and any fix application have completed.

---

## 1. Output Files

### Primary report

- **Filename**: `ultimate-code-review-report.md`
- **Location**: Repository root
- **Overwrites**: Yes, if a previous report exists at this path

### History archive

- **Filename**: `{YYYY-MM-DD}-{HHmmss}-{scope}-{strictness}.md`
- **Location**: `.ucr/history/` relative to repository root
- **Example**: `.ucr/history/2026-03-15-143022-full-strict.md`
- **Purpose**: Enables cross-review comparison over time
- **Create directory**: If `.ucr/history/` does not exist, create it before writing

The `scope` segment reflects the review scope (e.g., `full`, `src-only`, `api-routes`). The `strictness` segment reflects the configured strictness level (e.g., `strict`, `standard`, `lenient`).

### JSON companion (optional)

- **Filename**: `ultimate-code-review-report.json`
- **Location**: Repository root, alongside the markdown report
- **Purpose**: Structured findings for programmatic consumption (CI integration, dashboards, tracking)

### Triage report (conditional)

- **Filename**: `ultimate-code-review-triage.md`
- **Location**: Repository root
- **Triggered when**: The review determines the codebase is in a systemic failure state (e.g., majority of findings are Critical, no tests exist, fundamental architecture issues)

---

## 2. Secret Masking Protocol

Before writing ANY code snippet, configuration fragment, environment variable, or log output into the report, apply the secret masking pass. This is non-negotiable and applies to all report variants.

### Patterns to mask

| Pattern Type          | Examples                                                        |
| --------------------- | --------------------------------------------------------------- |
| API keys              | `sk-...`, `pk_live_...`, `AKIA...`, `ghp_...`, `xoxb-...`      |
| Tokens                | Bearer tokens, OAuth tokens, refresh tokens, session tokens     |
| Passwords             | Any value assigned to a key containing `password`, `passwd`, `secret`, `credential` |
| Connection strings    | Database URLs containing credentials (`postgres://user:pass@`) |
| Private keys          | PEM-encoded keys, SSH private keys, any `-----BEGIN...PRIVATE` |
| AWS credentials       | Access key IDs, secret access keys, session tokens              |
| JWT secrets           | Values assigned to `JWT_SECRET`, `SIGNING_KEY`, etc.            |
| Encryption keys       | Values assigned to `ENCRYPTION_KEY`, `AES_KEY`, `HMAC_SECRET`  |
| Webhook secrets       | Values assigned to `WEBHOOK_SECRET`, `SIGNING_SECRET`           |
| Generic secrets       | Any value for a key matching `*_SECRET`, `*_TOKEN`, `*_KEY`, `*_PASSWORD`, `*_CREDENTIAL` |

### Masking rules

1. **Replace the VALUE only.** Keep key names, file paths, line numbers, and surrounding code structure intact.

   Before masking:
   ```
   DATABASE_URL="postgres://admin:supersecret@db.example.com/prod"
   ```
   After masking:
   ```
   DATABASE_URL="[MASKED]"
   ```

2. **If a finding is ABOUT a secret exposure**, describe the type and location of the secret but NEVER include the actual value.

   Correct:
   > UCR-004: Hardcoded database password found in `src/config/db.ts` at line 12. The password is assigned directly to the `DB_PASSWORD` constant.

   Incorrect:
   > UCR-004: Hardcoded database password `supersecret` found in `src/config/db.ts` at line 12.

3. **Multi-line secrets** (e.g., PEM keys): Replace the entire block with `[MASKED: private key]` or `[MASKED: certificate]`.

4. **Heuristic fallback**: If a string value is high-entropy (long alphanumeric string with mixed case and symbols, 20+ characters) and appears in an assignment context, mask it and annotate: `[MASKED: possible secret]`.

5. **Never mask file paths, variable names, function names, or code structure.** Only mask literal secret values.

---

## 3. Report Structure

The report follows this exact section order. Every section is mandatory unless marked conditional. Do not reorder sections. Do not omit mandatory sections even if they have no findings (write "No findings in this category." instead).

### 3.1 Title Block

```markdown
# Ultimate Code Review Report

**Date**: {YYYY-MM-DD}
**Commit**: `{full commit hash}`
**Branch**: `{branch name}`
**Scope**: {what was reviewed}
**Strictness**: {strictness level}
**Review duration**: {how long the review took}
```

### 3.2 Executive Summary

3-5 sentences. Written for a technical decision-maker who will not read the full report. Must include:

- What the project is (type, stack, size)
- The overall state of the codebase (healthy, needs work, critical issues)
- The single most important finding
- Whether it is ready for release (one sentence)

### 3.3 Release Verdict

One of the following, displayed prominently:

| Verdict | Meaning |
| ------- | ------- |
| **Not fit for public release** | Critical issues that would cause data loss, security breaches, or service failure in production |
| **Fit for limited internal use only** | Functional but has issues that are acceptable for internal/team use, not external users |
| **Fit for staged beta with fixes** | Shippable to a controlled beta audience after addressing the listed blockers |
| **Fit for public release with minor fixes** | Production-ready with minor issues that should be fixed soon but do not block release |
| **Fit for public release** | No blocking issues found; standard maintenance recommended |

### 3.4 Verdict Justification

- Why this verdict was chosen (specific findings that drove the decision)
- What would change the verdict upward (specific actions)
- What would change the verdict downward (risks not fully explored)

### 3.5 Project Overview

Detected automatically from the repository:

- **Project type**: Web app, API, CLI, library, mobile app, monorepo, etc.
- **Tech stack**: Languages, frameworks, databases, key dependencies
- **Size**: File count, line count, dependency count
- **Detected tooling**: Test framework, linter, type checker, CI/CD, bundler, package manager

### 3.6 Review Scope and Assumptions

- What was reviewed (files, directories, patterns)
- What was excluded and why (vendor code, generated files, test fixtures, etc.)
- Assumptions made during the review (e.g., "assumed production database uses different credentials than .env.example")
- Limitations of the review (e.g., "no runtime testing performed", "third-party API behavior not verified")

### 3.7 .ucrconfig.yml Disclosure

For auditability, disclose the full contents of the project's `.ucrconfig.yml` if one exists. Specifically call out:

- **Exclusions**: Files or directories excluded from review
- **Accepted risks**: Any findings the user has explicitly accepted
- **Custom severity overrides**: Any finding categories with adjusted severity
- **Disabled categories**: Any review categories that were turned off

If no `.ucrconfig.yml` exists, state: "No .ucrconfig.yml found. Default settings were used for all review parameters."

### 3.8 Top Release Blockers

A numbered list of the most critical findings that block release. Maximum 10 items. Each entry includes:

- Finding ID
- One-line title
- Severity
- Why it blocks release (one sentence)
- Effort estimate to fix

If there are no release blockers, state: "No release blockers identified."

### 3.9 Findings by Severity

Four subsections, in order: Critical, Major, Moderate, Minor.

Each finding follows this format:

```markdown
#### UCR-{NNN}: {Title}

- **Severity**: {Critical | Major | Moderate | Minor}
- **Category**: {category}
- **Confidence**: {confirmed | high | possible}
- **Blocks release**: {yes | no}
- **File(s)**: `{path}:{line}` (list all affected files)

**Description**: {What the issue is and why it matters. 2-4 sentences.}

**Evidence**:
{Code snippet showing the issue, with secret masking applied.
 Include file path and line numbers. Keep snippets focused — show
 only the relevant lines plus minimal context.}

**Remediation**: {How to fix it. Be specific and actionable.
 Include a code example of the fix if it is straightforward.}

**Effort**: {Quick fix | Moderate | Significant refactor}
```

### 3.10 Findings by Category

Cross-reference the same findings organized by these 10 categories. Do not repeat the full finding detail; reference by ID and title with a link to the severity section.

1. Security vulnerabilities
2. Authentication and authorization
3. Data handling and validation
4. Error handling and resilience
5. Performance and scalability
6. Code quality and maintainability
7. Testing and test quality
8. Configuration and deployment
9. UI/UX (conditional: web/mobile apps only)
10. Accessibility (conditional: web/mobile apps only)

### 3.11 Bug Finder Report

Output from the dedicated bug-finding pass. Includes:

- Bugs found with evidence
- Logic errors
- Edge cases that produce incorrect behavior
- Off-by-one errors, null reference risks, unhandled states

### 3.12 Architecture Review

Output from the architecture analysis pass. Includes:

- Component structure assessment
- Dependency analysis (circular deps, tight coupling, dependency health)
- Data flow analysis
- Scalability considerations
- Separation of concerns assessment

### 3.13 Security Review

Output from the dedicated security analysis pass. Includes:

- Threat model summary (if applicable)
- Authentication/authorization review
- Input validation assessment
- Secrets management assessment
- Dependency vulnerability scan results
- OWASP Top 10 checklist (for web applications)

### 3.14 UI/UX Review (conditional)

Include only if the project is a web application, mobile application, or has a user-facing interface. Includes:

- Layout and visual consistency
- User flow analysis
- Error state handling (user-facing)
- Loading state handling
- Responsive design assessment

### 3.15 Accessibility Review (conditional)

Include only if the project has a user-facing interface. Includes:

- WCAG 2.1 AA compliance assessment
- Screen reader compatibility
- Keyboard navigation
- Color contrast
- ARIA usage

### 3.16 Test Quality

Assessment of the project's test suite. Includes:

- Coverage assessment (not a percentage — a qualitative assessment of what is and is not tested)
- Test quality (are tests testing the right things? are assertions meaningful?)
- Missing test categories (unit, integration, e2e, security, performance)
- Flaky test risk
- Test infrastructure assessment

### 3.17 Release Readiness

A structured checklist:

```markdown
| Category | Status | Notes |
|----------|--------|-------|
| Security | {Pass/Fail/Partial} | {notes} |
| Auth | {Pass/Fail/Partial/N/A} | {notes} |
| Data integrity | {Pass/Fail/Partial} | {notes} |
| Error handling | {Pass/Fail/Partial} | {notes} |
| Performance | {Pass/Fail/Partial} | {notes} |
| Testing | {Pass/Fail/Partial} | {notes} |
| Configuration | {Pass/Fail/Partial} | {notes} |
| Documentation | {Pass/Fail/Partial} | {notes} |
| Accessibility | {Pass/Fail/Partial/N/A} | {notes} |
| Deployment readiness | {Pass/Fail/Partial} | {notes} |
```

### 3.18 Per-Project-Type Verdicts (conditional)

Include only if the repository contains multiple project types (e.g., a monorepo with a frontend app and a backend API). Provide a separate release verdict for each project type with its own justification.

### 3.19 Overall Verdict

Restate the release verdict from section 3.3 with a final summary paragraph. This is the last thing a decision-maker reads if they skip to the end.

### 3.20 False Confidence Risks

Areas where the review's depth was limited and confidence is lower than the findings might suggest. Examples:

- "Third-party API error handling was reviewed statically but not tested against actual API failure modes."
- "Database query performance was assessed by reading queries, not by profiling against production-scale data."
- "The authentication flow was reviewed in isolation; full end-to-end auth testing was not performed."

This section exists to prevent false confidence. Never omit it.

### 3.21 Adversarial Pass Results

Results from the adversarial review phase, structured as:

- **Confirmed**: Findings from the primary review that the adversarial pass agrees with
- **Challenged**: Findings the adversarial pass disagrees with, and why
- **New findings**: Issues the adversarial pass found that the primary review missed
- **Disagreements resolved**: How challenges were adjudicated

### 3.22 Recommended Fix Order

An ordered list of findings to fix, prioritized by:

1. Security-critical issues first
2. Release blockers second
3. Then by effort-to-impact ratio (quick wins with high impact first)

Each entry includes:

```markdown
{priority}. **UCR-{id}**: {title} — Effort: {estimate}, Impact: {high/medium/low}
```

### 3.23 Fastest Path to Production Readiness

The minimum viable fix set to achieve a "Fit for public release" or "Fit for public release with minor fixes" verdict. This is not the ideal fix order; it is the shortest path.

- List only the fixes that would change the verdict
- Include effort estimates for each
- Provide a total effort estimate
- Be explicit about what risks are accepted by taking the fast path

### 3.24 History Comparison (conditional)

Include only if previous reports exist in `.ucr/history/`.

```markdown
### Comparison with Previous Review ({date of previous review})

| Status | Count | Findings |
|--------|-------|----------|
| Resolved since last review | {count} | UCR-{ids} |
| Remaining from last review | {count} | UCR-{ids} |
| New since last review | {count} | UCR-{ids} |

**Trend**: {Improving / Stable / Degrading} — {one sentence explanation}
```

### 3.25 Fix Summary (conditional)

Include only if fixes were applied during this review session. Use the format defined in the `offer-fixes.md` workflow.

### 3.26 Appendix

#### A. Raw Automated Tool Output

Include output from any automated tools that were run (linters, type checkers, security scanners). Apply secret masking before inclusion.

#### B. Possible-Confidence Findings

Findings where confidence was `possible` — things that might be issues but could not be confirmed through static review alone. Listed separately so they do not dilute the main findings.

#### C. Methodology Notes

- Review process description (multi-phase, adversarial, etc.)
- Tools and techniques used
- Time spent per phase
- Any deviations from the standard protocol

---

## 4. History Comparison Protocol

### Step 1: Check for previous reports

Look for files in `.ucr/history/` matching the pattern `*.md`. If the directory does not exist or is empty, skip history comparison.

### Step 2: Read the most recent report

Sort history files by filename (which encodes the date). Read the most recent one.

### Step 3: Extract previous findings

Parse the previous report's findings sections. Extract finding IDs and titles. If the previous report used a different ID scheme, match by title and file location instead.

### Step 4: Compare

For each finding in the current review:
- If a matching finding exists in the previous report: **Remaining**
- If no match exists in the previous report: **New**

For each finding in the previous report:
- If no match exists in the current review: **Resolved**

Matching criteria (in order of precedence):
1. Same finding ID referencing the same file and line range
2. Same title and same file (line numbers may have shifted)
3. Same category, same file, similar description (fuzzy match — note this in the comparison)

### Step 5: Assess trend

- **Improving**: More findings resolved than new findings introduced, or severity distribution shifted downward
- **Stable**: Roughly equal resolved and new, similar severity distribution
- **Degrading**: More new findings than resolved, or severity distribution shifted upward

---

## 5. JSON Companion Output

When generated, the JSON file contains:

```json
{
  "meta": {
    "date": "{YYYY-MM-DD}",
    "commit": "{full hash}",
    "branch": "{branch}",
    "scope": "{scope description}",
    "strictness": "{strictness level}",
    "verdict": "{release verdict string}"
  },
  "summary": {
    "total_findings": 0,
    "critical": 0,
    "major": 0,
    "moderate": 0,
    "minor": 0,
    "blockers": 0
  },
  "findings": [
    {
      "id": "UCR-001",
      "title": "{title}",
      "severity": "critical",
      "category": "{category}",
      "confidence": "confirmed",
      "blocks_release": true,
      "files": [
        {
          "path": "{relative path}",
          "lines": "{start}-{end}"
        }
      ],
      "description": "{full description}",
      "evidence": "{code snippet with secrets masked}",
      "remediation": "{fix guidance}",
      "effort": "quick-fix"
    }
  ],
  "history": {
    "previous_date": "{date or null}",
    "resolved": ["UCR-xxx"],
    "remaining": ["UCR-xxx"],
    "new": ["UCR-xxx"],
    "trend": "improving"
  }
}
```

Field notes:
- `severity` values: `"critical"`, `"major"`, `"moderate"`, `"minor"`
- `confidence` values: `"confirmed"`, `"high"`, `"possible"`
- `effort` values: `"quick-fix"`, `"moderate"`, `"significant-refactor"`
- `history` is `null` if no previous report exists
- Secret masking applies to `evidence` field values

---

## 6. Triage Report Variant

The triage report is a shorter, recovery-focused document generated when the codebase is in a state where the full report format would be overwhelming or counterproductive. It is triggered when:

- More than 50% of findings are Critical or Major severity
- No meaningful test coverage exists
- Fundamental architecture issues make incremental fixes insufficient

### Triage report structure

```markdown
# Ultimate Code Review — Triage Report

**Date**: {YYYY-MM-DD}
**Commit**: `{hash}`
**Verdict**: Not fit for public release — Triage mode

## Honest Assessment

{2-3 paragraphs. What works. What doesn't. No sugarcoating, but also
 no catastrophizing. Written for a developer who needs to understand
 the real state of things.}

## Systemic Diagnosis

{What are the root causes? Not individual findings, but the underlying
 patterns. Is it missing architecture? Accumulated tech debt? Missing
 expertise in a specific area? Time pressure? Each root cause gets a
 paragraph.}

## Top 5 Blockers

{The five most critical things. Each with a clear description and
 effort estimate. These are not necessarily the five highest-severity
 individual findings — they may be systemic issues that manifest as
 multiple findings.}

## What Works

{Genuinely positive aspects of the codebase. This section is mandatory.
 Even in triage mode, acknowledging what is working correctly matters
 for morale and prioritization. Do not fabricate positives. If very
 little works, say so honestly but find what does.}

## Remediation Roadmap

{Ordered phases:}

### Phase 1: Stop the bleeding ({effort estimate})
{Fixes that prevent active harm — security holes, data loss risks}

### Phase 2: Foundation ({effort estimate})
{Structural fixes — test infrastructure, error handling, core architecture}

### Phase 3: Hardening ({effort estimate})
{Quality improvements — validation, edge cases, performance}

### Phase 4: Release readiness ({effort estimate})
{Final polish — documentation, deployment config, monitoring}

## Total Estimated Effort to Release Readiness

{Honest range estimate. "X to Y developer-days" or "X to Y developer-weeks".
 State assumptions (team size, familiarity with codebase).}
```

---

## Behavioral Rules

- **Secret masking is mandatory.** Every code snippet, config fragment, and log output must pass through the masking protocol before being written to any report file.
- **Never omit mandatory sections.** If a section has no content, include it with a "No findings" or "Not applicable" note.
- **History directory creation is automatic.** If `.ucr/history/` does not exist, create it. Do not ask the user.
- **Overwrite the primary report.** The file at repo root is always the latest. History preserves previous versions.
- **JSON companion is opt-in.** Only generate it if the user's config requests it or the user asks for it.
- **Triage mode is automatic.** If the criteria are met, generate the triage report in addition to (not instead of) the full report.
- **Report must be self-contained.** A reader should be able to understand every finding without access to the codebase.
- **False Confidence Risks is never empty.** Every review has limitations. Document them.
