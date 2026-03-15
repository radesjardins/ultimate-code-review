---
name: ultimate-code-review
description: "Professional-grade code review for AI-generated code, security, architecture, and release readiness. Three review roles: bug finder, architecture reviewer, and release gate. Covers 10 categories including AI slop detection, security (OWASP), UX/accessibility, and performance. Supports whole-repo, diff, commit, or working-tree scope. Produces severity-ranked findings with code evidence, release verdicts, and optional fix application. Includes adversarial review pass, report history, local-only mode, and 8 project-type modules (web app, API, Chrome extension, CLI, library, Electron, mobile, SaaS)."
argument-hint: "[repo|diff|commit|tree] [--strictness mvp|production|public] [--engine claude|codex|both] [--local-only] [--fix blockers|critical-major|IDs]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - WebSearch
  - WebFetch
  - mcp__context7__resolve-library-id
  - mcp__context7__query-docs
---

<objective>
Run a professional-grade code review and produce a structured report with severity-ranked
findings, release verdict, and optional fix application.

**Orchestrator role:** Parse arguments, gather user choices, detect project context,
spawn review subagents with fresh context, handle checkpoints and adversarial passes,
offer fixes, assemble final report.

**Three report roles:**
1. Bug finder — functional correctness, edge cases, race conditions, state corruption
2. Architecture reviewer — coupling, boundaries, extensibility, patterns, maintainability
3. Release gate — security, secrets, dependencies, ops readiness, public defensibility

**Review dimensions:** Functional correctness, security, AI slop detection, architecture,
tests, performance, UI/UX, accessibility, release readiness, documentation, dependencies,
privacy/secrets handling.
</objective>

<execution_context>
**Load these files NOW before proceeding:**
- @{{UCR_DIR}}/workflows/orchestrate-review.md (main workflow)
- @{{UCR_DIR}}/references/severity-model.md (severity classification)
- @{{UCR_DIR}}/references/trust-model.md (trust boundaries)
</execution_context>

<context>
Arguments: $ARGUMENTS

**Scope options:** repo | diff | commit | tree
- `repo` — review all files in the repository
- `diff` — review staged + unstaged changes only
- `commit` — review files changed in HEAD commit only
- `tree` — review uncommitted working tree changes only

**Strictness:** mvp | production | public (default: production)
- `mvp` — focus on functional correctness, critical security, and stated goals
- `production` — full review across all dimensions
- `public` — production + open-source readiness, public scrutiny resilience, trust signals

**Engine:** claude | codex | both (default: claude)
- `claude` — Claude performs all review phases
- `codex` — Codex performs all review phases
- `both` — Claude does primary review (Phase 3), Codex does adversarial pass (Phase 4)

**Connectivity:** --local-only (default: internet-enabled)
**Fix mode:** --fix blockers | --fix critical-major | --fix id1,id2,...

**Project config:** .ucrconfig.yml (if present in repo root)
**History:** .ucr/history/ (previous review reports)
</context>

<process>
Execute the orchestrate-review workflow from
@{{UCR_DIR}}/workflows/orchestrate-review.md end-to-end.

Preserve all workflow gates, user checkpoints, and subagent boundaries.
</process>

<critical_rules>
1. **Always ask for scope** if not provided in arguments
2. **Disclose internet usage** before proceeding if not --local-only — state what will be accessed and why
3. **Never include secret values** in reports — show file, line, key name, and type only. Mask values completely in code snippets.
4. **Triage-first mode:** If project appears fundamentally broken (50+ critical findings or unsalvageable architecture), switch to triage report — verdict, systemic diagnosis, top 5-10 blockers, remediation roadmap. Say plainly if rebuild is warranted.
5. **Load .ucrconfig.yml** exclusions and accepted-risk rules if present. Surface all exclusions and accepted risks in the report for auditability.
6. **Save report** to .ucr/history/{timestamp}-{scope}-{strictness}.md after completion
7. **Compare against history** — if previous reports exist for this repo, summarize resolved, remaining, and newly introduced findings
8. **Secrets in config** — if .ucrconfig.yml contains accepted risks, validate they are still acknowledged, not stale
9. **Do not fabricate findings** — if you cannot verify something, mark confidence as "possible" and say what verification is needed
10. **Do not suppress findings** because they seem minor — rank them accurately and let severity speak. But do suppress findings that fail the evidence threshold for their severity level.
</critical_rules>

<success_criteria>
- [ ] User confirmed scope, strictness, engine, and connectivity
- [ ] Project type(s) detected and relevant modules loaded
- [ ] Primary review completed with findings
- [ ] Adversarial pass completed (if dual-engine or self-adversarial)
- [ ] Review-of-review pass completed (de-duplication, calibration)
- [ ] Findings presented to user with severity ranking
- [ ] Fix option offered (if findings exist)
- [ ] Report generated and saved
- [ ] History comparison included (if previous reports exist)
</success_criteria>
