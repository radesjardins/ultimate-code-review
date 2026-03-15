# Ultimate Code Review — Roadmap

## v1.0 (current)

The foundation. A complete, production-ready code review skill.

- Full 10-category review (functional, security, AI slop, architecture, tests, performance, UX, accessibility, release readiness, documentation)
- 8 project-type modules (web app, API, Chrome extension, CLI, library, Electron, mobile, SaaS)
- Sequential adversarial review (dual-engine mode with Claude and Codex)
- Review-of-review calibration pass
- Fix application with build/test validation
- Structured JSON report with severity-ranked findings
- Report history and comparison between runs
- `.ucrconfig.yml` project-level configuration
- GitHub Action for CI/CD (PR comments, check runs, artifact upload)
- Local-only mode (no network dependencies)
- Dependency vulnerability audit (npm, yarn, pnpm, pip, cargo, go, gem, composer)
- License compliance checking with copyleft detection
- Secrets scanning (gitleaks + pattern fallback, never exposes values)
- Cross-platform install (bash + PowerShell)

## v1.1 (planned)

Deeper domain-specific review capabilities.

- **Threat model mode** — Given an architecture description or diagram, enumerate attack surfaces, trust boundaries, and data flow risks. Produce a lightweight threat model alongside the code review.
- **API contract review** — Validate that implementation matches OpenAPI/Swagger schema. Detect undocumented endpoints, missing error responses, request/response type mismatches, and breaking changes between schema versions.
- **Schema/migration review** — Analyze database migrations for: data loss risk, missing rollback, index performance, constraint correctness, and compatibility with ORM models. Support for SQL migrations, Prisma, Alembic, ActiveRecord, and Flyway.
- **Infra/deploy config deep review** — Extended analysis of Dockerfiles, Kubernetes manifests, Terraform/Pulumi configs, CI/CD pipelines, and cloud IAM policies. Check for: overly permissive roles, missing resource limits, hardcoded regions, missing health checks, and drift between environments.

## v2.0 (planned)

Interactive and visual review capabilities, plus extensibility.

- **Accessibility deep-dive mode** — Interactive accessibility audit using Playwright to render pages, run axe-core, check keyboard navigation, verify ARIA attributes, test screen reader compatibility, and validate color contrast. Produces a per-page accessibility report with screenshots of violations.
- **UI/UX teardown mode** — Visual analysis via screenshots. Review layout consistency, spacing, typography hierarchy, interactive element sizing, loading states, error states, empty states, and responsive breakpoints. Requires screenshot input or Playwright rendering.
- **Performance-focused mode** — Integrate with profiling data (Lighthouse, webpack-bundle-analyzer, py-spy, Go pprof) to correlate code patterns with measured performance characteristics. Flag: unnecessary re-renders, N+1 queries visible in code, unbounded list rendering, missing pagination, synchronous operations that should be async.
- **Custom project-type module support** — User-defined project-type modules in `.ucr/project-types/` that extend or override built-in modules. Documented schema for creating new modules.
- **Team review workflows** — Assign findings to team members based on file ownership (CODEOWNERS), component areas, or severity. Integration with GitHub issues for tracking finding resolution.
- **Optional scoring/grading system** — Configurable quality score (0-100) based on weighted findings. Track score over time. Set minimum score thresholds for CI gates. Scoring is opt-in and fully configurable to avoid gaming.
- **Plugin system for custom checks** — Define custom review rules as small scripts or prompt fragments. Plugin interface for: pre-review hooks, custom pattern matchers, post-review transformers, and report formatters.

## v3.0 (future)

Cross-service intelligence and continuous operation.

- **Multi-repo/monorepo cross-service analysis** — Review changes in context of the full service graph. Detect: API contract breaks across services, shared schema drift, inconsistent error handling between producer/consumer, and deployment ordering dependencies. Requires service dependency map (auto-detected or configured).
- **Runtime behavior verification integration** — Correlate code review findings with runtime data from APM tools (Datadog, New Relic, Sentry). Validate that error handling actually works by checking production error rates. Flag code paths with high error rates that lack proper handling.
- **Production incident correlation** — Given a post-mortem or incident report, trace the root cause back to specific code patterns. When reviewing new code, flag patterns that previously caused incidents. Requires incident database or integration with incident management tools.
- **Continuous review mode** — Watch for code changes (via file watcher or git hooks) and run incremental reviews automatically. Maintain a rolling quality assessment. Alert when quality degrades beyond threshold. Designed for long development sessions where review at the end misses context.
