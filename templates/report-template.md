# Ultimate Code Review Report

<!-- UCR Report Template v1.0.0
     This template is populated by the Ultimate Code Review skill.
     Placeholder variables use {{curly_braces}} syntax.
     Do not remove section headers — the report parser depends on them.
     Sections with no findings should render "None." rather than being omitted. -->

**Date:** {{date}}
**Commit:** {{commit_hash}}
**Scope:** {{scope}}
**Strictness:** {{strictness}}
**Engine:** {{engine}}
**Review Duration:** {{duration}}

---

## Executive Summary

<!-- 3-5 sentences. Lead with the verdict, then the most important facts.
     Avoid hedging language — be direct about what was found. -->

{{executive_summary}}

## Release Verdict

**{{verdict}}**

{{verdict_justification}}

### What Would Change This Verdict

<!-- Specific, actionable conditions. Not "fix all bugs" — list the exact
     findings or categories that must be resolved before the verdict changes. -->

{{verdict_change_conditions}}

---

## Project Overview

| Attribute | Value |
|-----------|-------|
| Project Type | {{project_types}} |
| Stack | {{stack}} |
| Framework | {{framework}} |
| Files Reviewed | {{file_count}} |
| Lines of Code | {{loc_estimate}} |
| Test Coverage | {{test_coverage}} |
| Dependencies | {{dependency_count}} |

## Review Scope and Assumptions

<!-- Describe what was reviewed, what the review assumed about the deployment
     environment, and any limitations of the review (e.g., no runtime testing). -->

{{scope_description}}

### Configuration

<!-- Disclose which .ucrconfig.yml settings were active during this review.
     If no config file was found, state that defaults were used. -->

{{ucrconfig_disclosure}}

### Exclusions

<!-- List paths, files, or patterns that were excluded from review,
     either by .ucrconfig.yml exclude_paths or by scope constraints. -->

{{exclusions_list}}

### Accepted Risks

<!-- List any accepted_risks from .ucrconfig.yml that were active during
     this review. Include their expiry dates. Flag any that have expired. -->

{{accepted_risks_list}}

---

## Top Release Blockers

<!-- Numbered list of the findings that block release, ordered by impact.
     Each entry: finding ID, title, one-line reason it blocks release. -->

{{blockers_numbered_list}}

---

## Findings by Severity

### Critical ({{critical_count}})

<!-- Findings that represent security vulnerabilities, data loss risks,
     or fundamental correctness failures. Always block release. -->

{{critical_findings}}

### Major ({{major_count}})

<!-- Findings that represent significant bugs, architectural problems,
     or reliability risks. Block release at production/public strictness. -->

{{major_findings}}

### Moderate ({{moderate_count}})

<!-- Findings that represent code quality issues, missing validation,
     or maintainability concerns. Block release at public strictness only. -->

{{moderate_findings}}

### Minor ({{minor_count}})

<!-- Findings that represent style issues, minor improvements, or
     suggestions. Never block release on their own. -->

{{minor_findings}}

---

## Bug Finder Report

<!-- Summary of likely bugs found through code path analysis, edge case
     identification, and behavioral reasoning. Not just lint warnings. -->

{{bug_finder_summary}}

## Architecture Review

<!-- Assessment of code organization, separation of concerns, dependency
     structure, scalability considerations, and design pattern usage. -->

{{architecture_summary}}

## Security Review

<!-- Assessment of authentication, authorization, input validation,
     output encoding, cryptography usage, secrets management, and
     dependency vulnerabilities. Reference CWE/OWASP where applicable. -->

{{security_summary}}

## UI/UX Review

<!-- Assessment of user-facing behavior, error messaging, loading states,
     edge case handling in the UI, and consistency. Skip if not applicable. -->

{{ux_summary}}

## Accessibility Review

<!-- Assessment of WCAG compliance, keyboard navigation, screen reader
     support, color contrast, and semantic HTML. Reference WCAG criteria
     where applicable. Skip if not applicable. -->

{{accessibility_summary}}

## Test and Quality Review

<!-- Assessment of test coverage, test quality, missing test scenarios,
     flaky test indicators, and CI/CD configuration. -->

{{test_summary}}

## Release Readiness

<!-- Overall assessment of whether the project meets the bar for the
     configured strictness level. Consider documentation, deployment
     configuration, error handling, and monitoring readiness. -->

{{release_readiness_summary}}

---

## Per-Type Verdicts

<!-- Table of verdict per review type (security, architecture, etc.)
     Format:
     | Review Type | Verdict | Blocker Count | Key Issue |
     |-------------|---------|---------------|-----------|
-->

{{per_type_verdicts}}

## Overall Verdict

<!-- Final synthesized verdict considering all review types, the adversarial
     pass, and the configured strictness level. -->

{{overall_verdict}}

---

## False Confidence Risks

<!-- Areas where the codebase looks correct but the review has low confidence.
     Things that passed but might fail under conditions the review could not
     fully evaluate (e.g., concurrency, production load, specific browsers). -->

{{false_confidence_risks}}

## Adversarial Pass Results

<!-- The adversarial pass re-examines all findings from a skeptical perspective,
     looking for false positives, missed issues, and severity miscalibrations. -->

### Confirmed Findings

<!-- Findings that survived adversarial scrutiny unchanged. -->

{{confirmed_findings}}

### Challenged Findings

<!-- Findings whose severity or confidence was adjusted by the adversarial pass.
     Show original and revised values. -->

{{challenged_findings}}

### New Findings (from adversarial pass)

<!-- Issues discovered during the adversarial pass that were missed initially. -->

{{adversarial_new_findings}}

### Disagreements

<!-- Cases where the adversarial pass and initial review disagree and the
     disagreement was not resolved. Present both perspectives. -->

{{disagreements}}

---

## Recommended Fix Order

<!-- Ordered list of findings to fix, sequenced by: blocking status first,
     then dependency order (fix X before Y if Y depends on X), then effort
     (quick wins early for momentum). Each entry includes finding ID, title,
     effort estimate, and any prerequisite fixes. -->

{{fix_order_list}}

## Fastest Path to Production Readiness

<!-- Pragmatic advice: the minimum set of fixes needed to change the verdict
     to "ready for release" at the configured strictness level. Not the ideal
     fix list — the shortest path. -->

{{fastest_path}}

---

## History Comparison

<!-- If a previous report exists, show what changed: resolved findings,
     remaining findings, new findings, and trend direction.
     Render "No previous report available." if this is the first review. -->

{{history_comparison}}

## Fix Summary

<!-- If fixes were applied during the review session, summarize what was
     fixed, verify the fixes, and note any regressions introduced. -->

{{fix_summary}}

---

## Appendix

### A. Automated Tool Output

<!-- Raw or summarized output from any automated tools run during the review
     (linters, type checkers, security scanners, test suites). -->

{{automated_tool_output}}

### B. Possible-Confidence Findings

<!-- Findings marked as "possible" confidence — things that might be issues
     but require human judgment or runtime verification to confirm. -->

{{possible_findings}}

### C. Methodology Notes

<!-- Brief description of how the review was conducted, which passes were
     run, and any deviations from the standard review process. -->

{{methodology_notes}}

### D. Files Reviewed

<!-- Complete list of files included in the review scope.
     Format: one file path per line, optionally with line count. -->

{{files_reviewed_list}}
