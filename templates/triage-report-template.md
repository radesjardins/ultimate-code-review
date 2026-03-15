# Ultimate Code Review — Triage Report

<!-- UCR Triage Report Template v1.0.0
     This template is used instead of the full report when the project has
     systemic issues that make a standard per-finding review inappropriate.
     The triage report focuses on diagnosis and remediation planning rather
     than exhaustive finding enumeration. -->

**Date:** {{date}}
**Commit:** {{commit_hash}}
**Scope:** {{scope}}

---

## Verdict

**This project is not fit for release in its current state.**

<!-- Explain why a triage report was generated instead of a full review.
     Common triggers: overwhelming number of critical findings, missing
     fundamental infrastructure (no tests, no error handling), or
     architectural problems that invalidate per-finding analysis. -->

{{verdict_explanation}}

## Systemic Diagnosis

<!-- Identify the root causes behind the project's state. These are not
     individual bugs — they are patterns, missing practices, or structural
     decisions that produce large numbers of findings. Group related
     problems together. For each systemic issue, explain:
     - What the pattern is
     - How it manifests across the codebase
     - Why it matters (concrete consequences, not abstract concerns)
     - How widespread it is (approximate percentage of codebase affected) -->

{{systemic_diagnosis}}

## What Works

<!-- Acknowledge what is functioning correctly. This grounds the assessment
     in fairness and identifies foundations that remediation can build on.
     Be specific — not "some parts are okay" but "the authentication flow
     correctly validates tokens and handles expiry." -->

{{what_works}}

## Top Blockers (Priority Order)

<!-- Ordered list of the most impactful problems. Each blocker includes:

     **B1: {{blocker_title}}**
     - **What:** One-sentence description of the problem
     - **Why it blocks:** Concrete consequence if not addressed
     - **Effort:** Estimated effort to resolve (hours/days/weeks)
     - **Dependencies:** Other blockers that must be resolved first, or "None"
     - **Affected area:** Which parts of the codebase are impacted

     Number blockers B1, B2, B3, etc. for cross-referencing in the
     remediation roadmap. -->

{{blockers}}

## Remediation Roadmap

<!-- Phased plan for bringing the project to a reviewable state.
     Each phase should be completable independently and deliver
     measurable improvement.

     **Phase 1: {{phase_title}}** (Estimated: {{effort}})
     - Addresses blockers: B1, B3
     - Tasks:
       1. Specific actionable task
       2. Specific actionable task
     - Done when: Measurable completion criteria
     - Validates by: How to confirm the phase is complete

     After all phases, the project should be ready for a full UCR review.
     Do not try to fix everything in one phase — sequence by dependency
     order and impact. -->

{{remediation_phases}}

## Realistic Assessment

<!-- Honest effort estimates for reaching different readiness levels.
     These are rough estimates intended for planning, not commitments. -->

| Target | Estimated Effort | Key Prerequisites |
|--------|-----------------|-------------------|
| MVP-ready | {{mvp_effort}} | {{mvp_prereqs}} |
| Production-ready | {{prod_effort}} | {{prod_prereqs}} |
| Public-release-ready | {{public_effort}} | {{public_prereqs}} |

## Should You Rebuild?

<!-- Direct assessment of whether incremental fixes are the right approach
     or whether a partial/full rewrite would be more efficient. Consider:
     - How much of the codebase is salvageable
     - Whether the architecture supports the intended use case
     - Whether the tech stack is appropriate
     - The team's familiarity with the current code vs. alternatives
     - Time and resource constraints

     This section should give an honest recommendation, not default to
     "just fix it" or "rewrite everything." If the answer is "it depends,"
     specify what it depends on. -->

{{rebuild_assessment}}

---

## Appendix: Full Finding List

<!-- Even though the triage report focuses on systemic issues, include the
     complete finding list for reference. Use the standard finding format
     from findings-schema.md. Findings may be grouped by systemic issue
     rather than severity if that provides more useful organization.

     If the finding count is extremely high, summarize by category with
     counts and list only the top 10-15 most impactful findings in full. -->

{{all_findings}}
