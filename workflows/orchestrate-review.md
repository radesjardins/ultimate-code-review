# Ultimate Code Review — Main Workflow

This workflow is loaded by the orchestrator SKILL.md and executed end-to-end.

---

## Step 0: Parse Arguments and Resolve Defaults

Parse $ARGUMENTS for:
- **Scope**: repo | diff | commit | tree (if missing, ask user)
- **Strictness**: mvp | production | public (default: production)
- **Engine**: claude | codex | both (default: claude)
- **Local-only**: --local-only flag (default: internet-enabled)
- **Fix mode**: --fix blockers | --fix critical-major | --fix <ids> (default: no fixes)

If scope is missing, ask the user:

```
What would you like me to review?
1. Full repository (comprehensive — recommended for pre-release)
2. Current diff (staged + unstaged changes)
3. Latest commit (HEAD only)
4. Working tree (all uncommitted changes)
```

## Step 1: Connectivity Disclosure

If NOT --local-only:

```
This review will use internet access for:
- CVE/vulnerability database lookups for your dependencies
- License compliance checks against SPDX databases
- Framework documentation lookups via Context7

No source code or proprietary information is transmitted. Only package names,
versions, and documentation queries are sent.

Proceed with internet access? (yes / switch to local-only)
```

If user switches to local-only, note the restrictions:
- Dependency vulnerability checks limited to locally cached data
- License compliance based on package metadata only
- No framework-specific documentation lookups
- All code analysis, architecture review, and AI slop detection work fully offline

## Step 2: Load Project Config

Check for `.ucrconfig.yml` in the repository root:

```bash
ls .ucrconfig.yml 2>/dev/null
```

If present, read it and extract:
- `exclude_paths`: list of glob patterns to skip
- `accepted_risks`: list of acknowledged findings with justification
- `custom_rules`: list of project-specific review rules
- `strictness_override`: per-category strictness overrides
- `review_focus`: optional emphasis areas

If NOT present, proceed with defaults. Note in report: "No .ucrconfig.yml found — using default configuration."

## Step 3: Detect Project Context

Run the following detection steps:

### 3a: Repository Metadata
```bash
# Git info
git log --oneline -5 2>/dev/null
git rev-parse HEAD 2>/dev/null
git remote -v 2>/dev/null
```

Record: current commit hash (for report header and staleness tracking).

### 3b: Stack Detection

Detect languages, frameworks, and tooling by checking for:

| File/Pattern | Indicates |
|-------------|-----------|
| `package.json` | Node.js / JavaScript / TypeScript |
| `tsconfig.json` | TypeScript |
| `next.config.*` | Next.js |
| `vite.config.*` | Vite |
| `angular.json` | Angular |
| `vue.config.*` or `nuxt.config.*` | Vue / Nuxt |
| `requirements.txt`, `pyproject.toml`, `setup.py` | Python |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `Gemfile` | Ruby |
| `pom.xml`, `build.gradle` | Java / Kotlin |
| `Dockerfile`, `docker-compose.*` | Docker |
| `terraform/`, `*.tf` | Terraform |
| `manifest.json` (with `manifest_version`) | Chrome Extension |
| `electron-builder.*`, main/renderer split | Electron |
| `capacitor.config.*`, `ionic.config.*` | Mobile hybrid |
| `react-native.config.*`, `app.json` (expo) | React Native |
| `.github/workflows/` | GitHub Actions CI |
| `Makefile` | Make-based build |

Read detected config files to determine:
- Framework version
- Build tool
- Test framework
- Linter/formatter configuration
- Deployment target (if inferable)

### 3c: Project Type Classification

Based on detection, classify as one or more of:
- **web-app** — has UI components, routes, pages
- **api** — has route handlers, endpoints, schema definitions
- **chrome-extension** — has manifest.json with manifest_version
- **cli-tool** — has bin entry, commander/yargs/clap, no UI
- **library** — published package, exports API surface
- **electron-app** — has main/renderer process split
- **mobile-app** — React Native, Flutter, Capacitor, etc.
- **saas** — multi-tenant indicators, billing, auth system

A repo can match multiple types (e.g., web-app + api + saas).

### 3d: Trust Boundary Identification

Identify:
- External API integrations (HTTP clients, SDK imports)
- User input entry points (forms, URL params, CLI args, API endpoints)
- Authentication/authorization boundaries
- File system access points
- Database/storage access
- Third-party service integrations
- Environment variable usage
- Secret/credential references

### 3e: Scope File List

Based on the chosen scope, determine the file list:

```bash
# repo scope
git ls-files

# diff scope
git diff --name-only HEAD
git diff --name-only --cached

# commit scope
git diff --name-only HEAD~1 HEAD

# tree scope
git diff --name-only HEAD
git ls-files --others --exclude-standard
```

Apply .ucrconfig.yml exclusions. Remove files matching trust model exclusions
(node_modules/, vendor/, lockfiles, generated code).

Record total file count and estimated review scope.

## Step 4: Load Project-Type References

For each detected project type, load the corresponding reference:

```
@{{UCR_DIR}}/project-types/{type}.md
```

These provide type-specific review checklists and patterns.

Also load universal references:
```
@{{UCR_DIR}}/references/ai-slop-patterns.md
@{{UCR_DIR}}/references/security-checklist.md
@{{UCR_DIR}}/references/ux-accessibility-checklist.md
@{{UCR_DIR}}/references/release-readiness.md
```

## Step 5: Run Automated Checks (if available and permitted)

If NOT --local-only, and tools are available:

### 5a: Dependency Vulnerability Audit
```bash
# Node.js
npm audit --json 2>/dev/null || true
# Python
pip-audit --format json 2>/dev/null || true
# Rust
cargo audit --json 2>/dev/null || true
# Go
govulncheck ./... 2>/dev/null || true
```

### 5b: License Check
```bash
# Node.js
npx license-checker --json 2>/dev/null || true
# Python
pip-licenses --format=json 2>/dev/null || true
```

### 5c: Secrets Scan
```bash
# Use gitleaks if available
gitleaks detect --source . --report-format json --report-path /tmp/ucr-secrets.json 2>/dev/null || true
# Fallback: pattern-based grep for common secret patterns
```

### 5d: Existing Project Tools
If the project has configured linters, type checkers, or test suites, run them:

```bash
# Type checking
npx tsc --noEmit 2>/dev/null || true
# Linting
npx eslint . --format json 2>/dev/null || true
# Python
python -m mypy . 2>/dev/null || true
python -m ruff check . --output-format json 2>/dev/null || true
# Tests
npm test 2>/dev/null || true
pytest --tb=short 2>/dev/null || true
```

Capture output for inclusion as evidence in findings. Do not treat tool failures
as review failures — note what ran and what didn't.

### 5e: Build Verification
```bash
# Verify the project builds
npm run build 2>/dev/null || true
# Python
python -m build 2>/dev/null || true
# Go
go build ./... 2>/dev/null || true
```

## Step 6: Spawn Primary Review Subagent (Phase 3 — Deep Review)

Construct the review prompt with all gathered context and spawn a subagent:

```
Agent(
  subagent_type="general-purpose",
  description="UCR Deep Review",
  prompt="""
  You are a senior principal engineer, application security reviewer, and release manager
  performing a professional-grade code review.

  YOUR STANDARD IS NOT 'GOOD ENOUGH FOR A DEMO.'
  YOUR STANDARD IS PROFESSIONAL, PRODUCTION-READY, SECURE, MAINTAINABLE, AND PUBLICLY DEFENSIBLE CODE.

  ## Project Context
  - Type: {detected_types}
  - Stack: {detected_stack}
  - Framework: {detected_framework}
  - Scope: {scope} ({file_count} files)
  - Strictness: {strictness}
  - Commit: {commit_hash}
  - Trust boundaries: {trust_boundaries}
  - Config exclusions: {exclusions}
  - Accepted risks: {accepted_risks}

  ## Automated Check Results
  {automated_check_output}

  ## Your Review Must Cover

  ### 1. Functional Correctness
  - Broken logic, missing edge cases, inconsistent behavior
  - State corruption risks, race conditions
  - Invalid assumptions about external APIs or user behavior
  - Failure-mode behavior — what happens when things go wrong
  - User flows that appear complete but fail under real use

  ### 2. Security (use @security-checklist.md as reference)
  - Auth/authz issues, privilege escalation
  - Injection (SQL, XSS, CSRF, SSRF, command, path traversal, template)
  - Deserialization, open redirect, IDOR
  - Weak validation, unsafe file handling
  - Secrets in code, insecure defaults, session/token handling
  - Dependency vulnerabilities, supply chain concerns
  - Unsafe API trust assumptions
  - Privacy and data leakage
  - For AI-enabled apps: prompt injection vectors

  ### 3. AI Slop Detection (use @ai-slop-patterns.md as reference)
  - Hallucinated imports (packages/modules that don't exist)
  - Fake error handling (try/catch that swallows or log-and-continue)
  - Placeholder stubs that survived into production code
  - Silent failures (fake output matching desired format instead of crashing)
  - Cargo-cult patterns copied without understanding
  - Repetitive low-signal abstractions
  - Dead code, misleading comments, inconsistent naming
  - Over-engineering where simple code is safer
  - Under-engineering where structure is clearly needed
  - Code that removes safety checks to avoid errors

  ### 4. Architecture and Maintainability
  - Tight coupling, weak module boundaries
  - Unclear ownership of business logic
  - Config sprawl, poor dependency direction
  - Hidden side effects, fragile patterns
  - Cross-component interaction risks
  - Components that work in isolation but may fail in combination

  ### 5. Tests and Verification
  - Missing tests, shallow tests, brittle tests
  - False confidence from happy-path-only coverage
  - Missing integration/regression/security tests
  - Mismatch between implementation risk and test depth
  - Test setup that masks real behavior

  ### 6. Performance and Reliability
  - Unnecessary re-renders, slow queries, bad caching
  - Memory leaks, bundle bloat, blocking operations
  - Retry storms, bad timeout handling
  - Concurrency issues, scaling risks
  - Failure handling under degraded conditions

  ### 7. UI/UX (if applicable — use @ux-accessibility-checklist.md)
  - Mobile-first design, responsive layouts
  - Touch-target usability, thumb-first navigation
  - Error states, empty states, loading states
  - Keyboard usability, interaction cost
  - Visual hierarchy, typography, spacing
  - Real user flow friction analysis

  ### 8. Accessibility (if applicable)
  - Keyboard access, focus management
  - Semantic HTML structure, ARIA usage
  - Color contrast, reduced-motion
  - Form labeling, status messaging
  - Screen reader considerations

  ### 9. Release Readiness (use @release-readiness.md)
  - Environment config, setup clarity
  - Build reliability, CI/CD assumptions
  - Secrets/config separation
  - Rollback readiness, logging, error monitoring
  - Migration risks, licensing concerns

  ### 10. Documentation and Developer Experience
  - README usefulness and accuracy
  - Setup instructions completeness
  - Architecture clarity
  - Missing env var documentation
  - Misleading or outdated docs

  ## Severity Model
  Use @severity-model.md. Every finding must include:
  - ID (UCR-NNN)
  - Title
  - Severity: critical | major | moderate | minor
  - Category (from the 10 above)
  - Confidence: confirmed | probable | possible
  - Affected files with line numbers
  - Code evidence (the actual problematic code, with secrets masked)
  - Why it matters (specific impact, not generic)
  - How to verify or reproduce
  - Recommended fix (concrete, not vague)
  - Blocks release: yes | no | conditional

  ## Evidence Thresholds
  - Critical: file + line + code snippet + reproduction path + impact assessment
  - Major: file + line + code snippet + reasoning
  - Moderate: file + line + reasoning
  - Minor: file + description

  ## Confidence Levels
  - Confirmed: verified by reading the code — the issue is present
  - Probable: strong inference from code patterns — very likely present
  - Possible: suspicious but needs manual validation — flag for human review

  ## Rules
  - Do NOT fabricate findings. If uncertain, mark as "possible."
  - Do NOT pad the report with low-value nits to appear thorough.
  - Do NOT use vague language ("consider improving," "might want to").
  - Be specific. Be direct. Show the code. Explain the impact.
  - If a category has zero findings, state that explicitly with your confidence level.
  - Cross-reference findings: if a security issue is also an architecture issue, note both.
  - Track whether findings are in excluded paths or accepted risks from .ucrconfig.yml.

  ## Output Format
  Return your findings as a structured list grouped by severity, then by category.
  Start with: ## REVIEW COMPLETE
  Then: ### Summary (counts by severity and category)
  Then: ### Findings (each with full structure above)
  Then: ### Zero-Finding Categories (what you reviewed and found clean, with confidence)
  Then: ### Automated Tool Results Summary
  Then: ### Scope Limitations (what you could not adequately review and why)

  ## Files to Review
  {scoped_file_list}

  Read every file in the scope. Do not skip files. Do not sample.
  For large repos (500+ files), prioritize: entry points, auth, API handlers, config,
  then remaining files by likely risk.
  """
)
```

## Step 7: Handle Primary Review Return

Parse the subagent's return for `## REVIEW COMPLETE`.

Extract:
- Finding count by severity
- Finding count by category
- Zero-finding categories with confidence
- Scope limitations

If finding count exceeds 50 critical findings OR the reviewer flagged fundamental
architecture issues, switch to **triage-first mode**:
- Skip adversarial pass
- Skip standard report generation
- Jump to Step 12 (Triage Report)

Otherwise, continue to adversarial pass.

## Step 8: Adversarial Pass (Phase 4)

### If engine = "both" (Sequential Adversarial)

The second engine reviews the repository AND the first engine's findings:

```
Agent(
  subagent_type="general-purpose",
  description="UCR Adversarial Review",
  prompt="""
  You are an adversarial code reviewer. Your job is to challenge, verify, and improve
  upon a primary review that was already performed.

  ## Your Role
  You are NOT rubber-stamping. You are looking for:
  1. False positives in the primary review (findings that are wrong or overstated)
  2. False negatives (real issues the primary review missed)
  3. Severity miscalibration (findings rated too high or too low)
  4. Missing cross-component interaction issues
  5. Missing threat cases at trust boundaries
  6. UX/accessibility issues not caught in code review
  7. AI slop patterns that survived the first pass

  ## Primary Review Findings
  {primary_review_findings}

  ## Adversarial Protocol (from @adversarial-protocol.md)

  For each HIGH-SEVERITY finding from the primary review:
  - What evidence would make this a false positive?
  - Read the actual code and verify the claim.
  - If the evidence holds, mark as CONFIRMED.
  - If the evidence is weak, mark as CHALLENGED with reasoning.

  For each CATEGORY with zero findings:
  - What class of bug would hide here?
  - Are there files in this category that weren't adequately reviewed?
  - Perform targeted checks for the most likely missed issues.

  For each TRUST BOUNDARY identified:
  - What happens if the other side sends malformed data?
  - What happens if the other side is compromised?
  - What happens under partial failure?

  For each CROSS-COMPONENT INTERACTION:
  - Do components agree on data formats, field counts, error handling?
  - Are there timing assumptions that could break under load?
  - Are there state assumptions that could break under concurrent access?

  ## Output Format
  Return with: ## ADVERSARIAL REVIEW COMPLETE
  Then:
  ### Confirmed Findings (primary findings you verified — list IDs)
  ### Challenged Findings (primary findings you disagree with — ID, reasoning, new severity)
  ### New Findings (issues you found that the primary review missed — full finding format)
  ### Severity Adjustments (findings that need re-rating — ID, old severity, new severity, reasoning)
  ### Disagreements (explicit section for any substantive disagreement with primary review)

  ## Files to Review
  {scoped_file_list}
  """
)
```

### If engine = "claude" or "codex" (Self-Adversarial)

Use the same adversarial protocol but as a single-engine self-challenge:

```
Agent(
  subagent_type="general-purpose",
  description="UCR Self-Adversarial Pass",
  prompt="""
  You performed a primary review that produced the findings below.
  Now challenge your own work using the adversarial protocol.

  Your goal: reduce false positives, find false negatives, and calibrate severity.

  {same adversarial prompt structure as above, adapted for self-review}
  """
)
```

## Step 9: Review of the Review (Phase 5)

After the adversarial pass, merge and calibrate:

1. **Merge findings**: Combine primary + adversarial new findings
2. **Apply challenges**: For challenged findings, evaluate the adversarial reasoning.
   If the challenge is well-supported, downgrade or remove. If weak, keep original.
3. **Apply severity adjustments**: Accept well-reasoned re-ratings
4. **De-duplicate**: Merge overlapping findings into single entries
5. **Confidence check**: Any finding with only "possible" confidence and no code evidence
   should be moved to an appendix, not the main findings list
6. **Blocker validation**: Re-verify every finding marked "blocks release: yes"
   - Does it have confirmed/probable confidence?
   - Does it have code evidence?
   - Would a senior engineer agree this blocks release?
7. **Noise check**: If the report has more than 30 minor findings, consolidate into
   category summaries. The report should not be a wall of nits.
8. **Completeness check**: Are all 10 review categories represented? If a category
   has no findings, is the "zero finding" confidence level reasonable?

Record the final calibrated finding list.

## Step 10: Present Findings to User

Display a summary:

```
## Review Complete

**Scope:** {scope} | **Strictness:** {strictness} | **Engine:** {engine}
**Commit:** {commit_hash}
**Files reviewed:** {file_count}

### Finding Summary
| Severity | Count | Blocks Release |
|----------|-------|----------------|
| Critical | N     | N              |
| Major    | N     | N              |
| Moderate | N     | -              |
| Minor    | N     | -              |

### Release Verdict
{verdict} — {one-line justification}

### Top Findings
{top 5 findings by severity, one line each with ID, title, severity, file}
```

Then ask:

```
What would you like to do?
1. View full findings (by severity or by category)
2. Apply fixes — choose preset:
   a. Blockers only (N findings)
   b. Critical + Major (N findings)
   c. Select specific finding IDs
3. Generate full report (saves to ultimate-code-review-report.md)
4. Generate report and apply fixes
```

## Step 11: Fix Application (if requested)

Load the fix workflow:
```
@{{UCR_DIR}}/workflows/offer-fixes.md
```

### Fix Protocol Summary:

1. **Scope selection**: User chooses preset or specific IDs
2. **Conflict detection**: If fix A conflicts with fix B, prioritize higher-severity
   or wider-scope fix. Defer the conflicting one. Document conflict in report.
3. **Fix grouping**: Group fixes into logical units (e.g., "auth fixes," "validation fixes")
4. **For each fix group**:
   a. Apply fixes
   b. Run targeted validation immediately:
      - If tests exist for affected code, run them
      - If type checker is configured, run it on affected files
      - If linter is configured, run it on affected files
      - Verify the fix addresses the finding
   c. Commit: one commit per logical fix group
      - Message format: `fix(ucr): {group description} [UCR-{ids}]`
5. **After all fix groups**: Run final scoped re-review of affected areas
   plus blocker revalidation
6. **Report deferred fixes**: List fixes that were deferred due to conflicts,
   with explanation and recommended manual resolution

## Step 12: Report Generation

Load the report workflow:
```
@{{UCR_DIR}}/workflows/report-generation.md
```

### Report Generation Summary:

Generate `ultimate-code-review-report.md` in the repository root using the report template.

The report must include:
1. Executive summary
2. Release verdict with justification
3. Project overview (inferred from repo)
4. Review scope, commit hash, and assumptions
5. Configuration (.ucrconfig.yml exclusions and accepted risks)
6. Top release blockers
7. Findings by severity (with full evidence)
8. Findings by category
9. Bug finder summary
10. Architecture review summary
11. Security review summary
12. UI/UX review summary (if applicable)
13. Accessibility review summary (if applicable)
14. Test and quality review summary
15. Release readiness summary
16. Per-project-type verdicts (if multi-type repo)
17. Overall release verdict
18. False confidence risks (areas where review depth was limited)
19. Adversarial pass results (disagreements, challenges, new findings)
20. Recommended fix order
21. Fastest path to production readiness
22. History comparison (if previous reports exist)
23. Appendix: automated tool output, possible-confidence findings, evidence notes

### Secret Masking
Before writing the report:
- Scan all code snippets for values that look like secrets (API keys, tokens, passwords, connection strings)
- Replace values with `[MASKED]` but preserve key names and context
- Example: `API_KEY = "sk-1234..."` becomes `API_KEY = "[MASKED]"`

### History
```bash
mkdir -p .ucr/history
```

Save report to `.ucr/history/{YYYY-MM-DD}-{scope}-{strictness}.md`

If previous reports exist:
```bash
ls -t .ucr/history/*.md | head -1
```

Read the most recent report and compare:
- Which previous findings are now resolved?
- Which previous findings remain?
- Which findings are newly introduced?

Include this comparison as a "History Comparison" section in the report.

## Step 12T: Triage Report (if fundamentally broken)

If the project triggered triage-first mode (Step 7):

Generate a triage report instead of the full report:

1. **Clear verdict**: "This project is not fit for release in its current state."
2. **Systemic diagnosis**: What is fundamentally wrong — not individual findings, but the pattern.
   Examples: "No authentication system exists," "The architecture is a single 3000-line file,"
   "All error handling is fake," "The database schema has no constraints."
3. **Top 5-10 blockers**: The most important things to fix first, in order.
   Each with: what, why, scope of effort, dependencies between them.
4. **Remediation roadmap**: Ordered phases to recover the project.
   If incremental repair is a worse investment than partial rewrite, say so plainly.
5. **What works**: Be honest about what IS good. Don't make it a wall of negativity.
6. **Realistic assessment**: How much work would it take to reach each strictness level?

Save triage report as `ultimate-code-review-triage.md` in repo root.

## Step 13: Wrap Up

After report generation:

1. Display the report file path
2. If fixes were applied, list the commits created
3. If deferred fixes exist, list them with instructions
4. Remind user of the commit hash the review was performed against
5. Suggest when to re-run (after significant changes, before next release)

```
## Review Complete

Report saved: ultimate-code-review-report.md
History saved: .ucr/history/{filename}

Reviewed at commit: {hash}
This report reflects the codebase at that point in time.
Re-run after significant changes for updated findings.
```
