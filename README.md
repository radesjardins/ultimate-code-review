# Ultimate Code Review

Professional-grade code review skill for Claude Code and Codex that catches AI slop, security issues, architecture problems, and release blockers.

## What It Does

UCR performs three review roles on every run:

1. **Bug Finder** — Hunts for functional defects, logic errors, race conditions, edge cases, unhandled errors, and the specific failure patterns common in AI-generated code (hallucinated imports, fake error handling, placeholder stubs, silent failures).

2. **Architecture Reviewer** — Evaluates structure, coupling, naming, abstraction quality, test coverage gaps, performance footguns, and maintainability. Flags code that works today but will cause pain at scale.

3. **Release Gate** — Checks security, accessibility, license compliance, dependency vulnerabilities, secret exposure, and documentation completeness. Answers: "Is this safe to ship?"

Each finding includes severity, category, file location, code evidence, and a concrete fix suggestion.

## Why This Exists

AI-generated code compiles and passes basic tests but has measurable quality issues: hallucinated APIs, shallow error handling, missing edge cases, copy-paste patterns that diverge, and security assumptions that don't hold. Human review catches some of this, but reviewers have finite attention and inconsistent coverage.

UCR is the harsh reviewer that runs AFTER the build phase. It is intentionally adversarial — it assumes the code is wrong and looks for proof. When it finds nothing, that is a meaningful signal.

## Quick Start

### Installation

**From GitHub (recommended):**

```bash
git clone https://github.com/[owner]/ultimate-code-review.git
cd ultimate-code-review

# Unix / macOS / Git Bash
./install.sh

# Windows PowerShell
.\install.ps1
```

**Manual copy:**

```bash
# Copy the skill file
mkdir -p ~/.claude/skills/ultimate-code-review
cp skill/SKILL.md ~/.claude/skills/ultimate-code-review/

# Copy supporting files
mkdir -p ~/.ai-shared/ucr
cp -r references workflows project-types templates scripts ~/.ai-shared/ucr/
chmod +x ~/.ai-shared/ucr/scripts/*.sh
```

### Usage

In Claude Code, the skill activates automatically when you request a code review:

```
/review                          # Review current diff (default)
/review --scope repo             # Review entire repository
/review --scope commit           # Review last commit
/review --scope tree             # Review working tree changes
/review --strictness public      # Strict review for public release
/review --engine both            # Run Claude then Codex adversarial pass
```

Or invoke directly:

```
Review this codebase with UCR at production strictness.
Run a security-focused review on the src/ directory.
Review the last 3 commits for release readiness.
```

### Review Scopes

| Scope    | What It Reviews                        | When To Use                        |
|----------|----------------------------------------|------------------------------------|
| `diff`   | Staged/unstaged changes or PR diff     | Default for PRs and quick checks   |
| `commit` | Specific commit(s)                     | Post-merge review                  |
| `tree`   | All modified files in working tree     | Before committing                  |
| `repo`   | Entire repository                      | Initial audit, periodic deep review|

### Strictness Levels

| Level        | Behavior                                                     |
|--------------|--------------------------------------------------------------|
| `mvp`        | Focus on blockers and critical bugs. Skip style, docs, minor issues. Fast. |
| `production` | Full review across all 10 categories. Default.               |
| `public`     | Everything in production plus: public API surface, docs completeness, license compliance, security hardening. |

### Engine Options

| Engine   | Behavior                                                       |
|----------|----------------------------------------------------------------|
| `claude` | Single-pass review using Claude. Default.                      |
| `codex`  | Single-pass review using Codex.                                |
| `both`   | Sequential adversarial: Claude reviews first, then Codex reviews Claude's findings and looks for what was missed. |

The `both` mode produces the highest-quality results. The second engine acts as an adversarial reviewer — it challenges the first engine's findings, removes false positives, and adds findings the first engine missed.

## Features

- **10-category review**: Functional correctness, security, AI slop detection, architecture, tests, performance, UX, accessibility, release readiness, documentation
- **8 project-type modules**: Web app, API/backend, Chrome extension, CLI tool, library/package, Electron app, mobile (React Native/Flutter), SaaS platform
- **Severity-ranked findings** with file, line, code evidence, and fix suggestions
- **AI slop detection**: Hallucinated imports, fake error handling, placeholder stubs, silent `catch {}` blocks, TODO-as-implementation, copy-paste divergence
- **Adversarial review pass**: Second engine challenges the first engine's work
- **Review-of-review calibration**: Final pass removes false positives, adjusts severity
- **Fix application with validation**: Apply suggested fixes and verify they don't break anything
- **Report history and comparison**: Track review results over time, diff between runs
- **Local-only mode**: All checks run without network access (uses cached/local data only)
- **GitHub Action**: Automated review on PRs, manual triggers, scheduled runs
- **Dependency vulnerability audit**: Supports npm, yarn, pnpm, pip, cargo, go, gem, composer
- **License compliance checking**: Flags copyleft licenses in non-GPL projects, unknown licenses
- **Secrets scanning**: Uses gitleaks or pattern-based fallback, never exposes secret values
- **Configurable via `.ucrconfig.yml`**: Project-level settings for scope, strictness, ignores

## Configuration

Create a `.ucrconfig.yml` in your project root to customize behavior:

```yaml
# .ucrconfig.yml
version: 1

# Default review settings
defaults:
  scope: diff
  strictness: production
  engine: claude

# Project type (auto-detected if omitted)
# Options: web-app, api, chrome-extension, cli, library, electron, mobile, saas
project_type: web-app

# Categories to skip
skip_categories: []
  # - documentation
  # - accessibility

# Paths to exclude from review
exclude_paths:
  - "vendor/**"
  - "dist/**"
  - "*.min.js"
  - "**/*.generated.*"

# Severity threshold — only report findings at or above this level
min_severity: info  # info | warning | critical | blocker

# Custom patterns for AI slop detection
ai_slop_patterns: []
  # - pattern: "// TODO: implement"
  #   severity: critical
  #   message: "Placeholder stub left in code"

# License compliance
licenses:
  # Allowed licenses (others will be flagged)
  allowed: []
    # - MIT
    # - Apache-2.0
    # - BSD-2-Clause
    # - BSD-3-Clause
    # - ISC
  # Denied licenses (always flagged)
  denied: []
    # - GPL-3.0
    # - AGPL-3.0

# Report history
history:
  enabled: false
  directory: .ucr/history
```

## GitHub Action

Add automated code review to your CI/CD pipeline.

### Setup

1. Copy the workflow file to your project:

```bash
mkdir -p .github/workflows
cp ~/.ai-shared/ucr/.github/workflows/ultimate-code-review.yml .github/workflows/
```

2. Add required secrets to your GitHub repository:
   - `ANTHROPIC_API_KEY` — Required for Claude engine
   - `OPENAI_API_KEY` — Required for Codex engine

3. (Optional) Create `.ucr/history/` directory to enable report archival.

### Configuration

The workflow supports these inputs (via `workflow_dispatch`):

| Input       | Options                        | Default      |
|-------------|--------------------------------|--------------|
| `scope`     | repo, diff, commit, tree       | repo         |
| `strictness`| mvp, production, public        | production   |
| `engine`    | claude, codex, both            | claude       |
| `blocking`  | true, false                    | false        |

When `blocking` is enabled, only confirmed critical/blocker findings will fail the check. This is off by default — UCR reports findings but does not block merges unless you opt in.

### PR Comments

On pull request triggers, UCR posts a summary comment with findings. The comment is updated on subsequent pushes to the same PR (no comment spam).

## Report Format

UCR produces a structured JSON report containing:

- Metadata (timestamp, scope, strictness, engine, duration)
- Findings array, each with: severity, category, file, line, description, evidence, fix suggestion
- Audit results (dependency vulnerabilities, license flags, secrets findings)
- Summary statistics (counts by severity, counts by category)
- Comparison with previous report (if history is enabled)

Reports are saved to `.ucr/reports/` and optionally committed to `.ucr/history/`.

## Architecture

```
User triggers review
        |
        v
   Orchestrator (SKILL.md)
        |
        +-- Detects project type
        +-- Loads project-type module
        +-- Determines scope (diff/commit/tree/repo)
        |
        v
   Pre-review scripts (parallel)
        +-- dep-audit.sh    -> dependency vulnerabilities
        +-- license-check.sh -> license compliance
        +-- secrets-scan.sh  -> secret detection
        |
        v
   Primary review (Engine 1)
        +-- 10-category analysis
        +-- Project-type-specific checks
        +-- AI slop detection
        |
        v
   Adversarial pass (Engine 2, if --engine both)
        +-- Challenge Engine 1 findings
        +-- Find missed issues
        +-- Remove false positives
        |
        v
   Calibration pass
        +-- Deduplicate
        +-- Adjust severity
        +-- Final false-positive filter
        |
        v
   Report generation
        +-- JSON report
        +-- Markdown summary
        +-- History comparison (if enabled)
        +-- Fix suggestions
```

## Project Structure

```
ultimate-code-review/
  skill/
    SKILL.md                  # Main skill definition (the orchestrator)
  references/
    ai-slop-patterns.md       # AI slop detection reference
    security-checklist.md      # Security review checklist
    review-categories.md       # 10-category definitions
  workflows/
    review-workflow.md         # Step-by-step review process
    adversarial-workflow.md    # Dual-engine adversarial process
    fix-workflow.md            # Fix application process
  project-types/
    web-app.md                # Web application module
    api.md                    # API/backend module
    chrome-extension.md       # Chrome extension module
    cli.md                    # CLI tool module
    library.md                # Library/package module
    electron.md               # Electron app module
    mobile.md                 # Mobile app module
    saas.md                   # SaaS platform module
  templates/
    report-template.json      # Report JSON structure
    ucrconfig-template.yml    # Default .ucrconfig.yml
  scripts/
    dep-audit.sh              # Dependency vulnerability audit
    license-check.sh          # License compliance check
    secrets-scan.sh           # Secrets detection
  .github/
    workflows/
      ultimate-code-review.yml  # GitHub Action workflow
  install.sh                  # Unix/macOS/Git Bash installer
  install.ps1                 # Windows PowerShell installer
  README.md                   # This file
  ROADMAP.md                  # Version roadmap
  LICENSE                     # MIT License
```

## Contributing

1. Fork the repository.
2. Create a feature branch.
3. Make your changes. Keep the skill definition (`SKILL.md`) and reference docs in sync.
4. Test with `./install.sh` and run a review on a sample project.
5. Submit a pull request with a clear description of what changed and why.

For new project-type modules, follow the structure of existing modules in `project-types/`.

For new review categories, update both the skill definition and `references/review-categories.md`.

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgments

- Research on AI code quality issues from academic and industry sources
- OWASP security checklists and CWE database for security review patterns
- WCAG 2.1 guidelines for accessibility checks
- SPDX license list for license compliance
- gitleaks project for secrets detection patterns
