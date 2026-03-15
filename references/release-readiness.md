# Release Readiness Checklist

This document defines what must be true before code can be released, organized by strictness level. Each item indicates which strictness levels require it.

Strictness levels:
- **mvp**: Minimum viable product. Internal use, limited users, high tolerance for rough edges.
- **production**: Production deployment for real users. Reliability and security matter.
- **public**: Open source release or public-facing product launch. Reputation, trust, and legal compliance matter.

Items marked with a strictness level are REQUIRED at that level and all higher levels. An item marked `[production]` is required for production AND public.

---

## 1. Environment and Configuration

### 1.1 Environment Variables Documented `[mvp]`

**What to check**: Every environment variable the application needs is documented somewhere (README, .env.example, or dedicated config docs).

**How to verify**:
- Find all `process.env`, `os.environ`, `os.Getenv`, `System.getenv` references in code
- Cross-reference with documentation
- Every variable should have: name, description, required/optional, example value (not real value), default if any

**Release gate**: Application cannot start without required env vars, and it's clear which ones are needed.

### 1.2 No Hardcoded Environment-Specific Values `[mvp]`

**What to check**: No localhost URLs, development API keys, or staging database connections in committed code.

**How to verify**:
- Search for `localhost`, `127.0.0.1`, `0.0.0.0` in non-configuration files
- Search for environment-specific URLs: staging domains, internal hostnames
- Search for hardcoded ports that should be configurable
- Check database connection strings: must come from environment, not source code

**Release gate**: Application can be deployed to any environment by changing env vars only.

### 1.3 .env.example Exists `[mvp]`

**What to check**: An `.env.example` or `.env.template` file exists with all required variables and placeholder values.

**How to verify**:
- File exists at project root
- Contains every required environment variable
- Values are clearly placeholders (`your-api-key-here`, `changeme`, `<required>`)
- No real secrets in the example file

### 1.4 Secrets Not in Source Code `[mvp]`

**What to check**: No API keys, passwords, tokens, or connection strings with real credentials in any committed file.

**How to verify**:
- Search for high-entropy strings in source files
- Search for known secret patterns: `sk_live_`, `AKIA`, `-----BEGIN`, `mongodb+srv://`, `postgres://.*:.*@`
- Check test fixtures and seed files
- Check CI/CD configuration files

**Release gate**: Hard block at ALL levels. Committed secrets are always Critical.

### 1.5 Configuration Separation `[production]`

**What to check**: Development, staging, and production configurations are separated and cannot be accidentally mixed.

**How to verify**:
- Check for environment detection: `NODE_ENV`, `RAILS_ENV`, `FLASK_ENV`, `ASPNETCORE_ENVIRONMENT`
- Verify different configs per environment (logging level, debug mode, error detail, etc.)
- Check that debug/development features are disabled in production config
- Verify there's no "if production, then..." scattered throughout the code (should be centralized config)

---

## 2. Build and CI/CD

### 2.1 Build Succeeds Without Warnings `[production]`

**What to check**: The build process completes successfully. Compiler/linter warnings are addressed.

**How to verify**:
- Run the build command
- Check for warnings in output (TypeScript strict mode warnings, deprecation warnings, unused variable warnings)
- Warnings in production builds indicate potential issues

### 2.2 CI Pipeline Exists and Passes `[production]`

**What to check**: An automated CI pipeline runs on every commit/PR and currently passes.

**How to verify**:
- Check for CI configuration: `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, `bitbucket-pipelines.yml`, `.circleci/config.yml`
- Verify the pipeline runs: lint, type check, test, build
- Check that the pipeline runs on pull requests (not just main branch)

### 2.3 Linting Configured and Passing `[production]`

**What to check**: A linter is configured and all source files pass.

**How to verify**:
- Check for linter config: `.eslintrc`, `pyproject.toml` (ruff/flake8), `rustfmt.toml`, `.golangci.yml`
- Verify linter runs in CI
- Check for disabled rules: a few targeted disables are fine, widespread `eslint-disable` is a red flag

### 2.4 Type Checking Configured and Passing `[production]`

**What to check**: For typed languages (TypeScript, Python with mypy/pyright, Rust, Go, Java), type checking is configured and passes.

**How to verify**:
- Check for TypeScript: `tsconfig.json` with `strict: true` (or at least `noImplicitAny: true`)
- Check for Python: `mypy.ini`, `pyproject.toml` with mypy/pyright config
- Verify type checking runs in CI
- Check for `@ts-ignore`, `type: ignore`, `# type: ignore` usage (should be rare and justified)

### 2.5 Build Output Is Reproducible `[production]`

**What to check**: The same source code produces the same build output.

**How to verify**:
- Lockfile is committed and used during CI builds (`npm ci`, not `npm install`)
- Docker images use specific version tags, not `latest`
- No build-time dependency on external state (current time, random values, network fetches during build)

---

## 3. Testing

### 3.1 Critical Path Tests Exist `[mvp]`

**What to check**: Tests exist for the most important functionality -- the paths that, if broken, make the application useless.

**How to verify**:
- Identify the 3-5 most critical user flows
- Verify at least one test covers each flow
- Tests should test behavior (input/output), not implementation details

**Minimum for mvp**: If only 5 tests exist, they should cover the 5 most important things.

### 3.2 Unit and Integration Tests `[production]`

**What to check**: Comprehensive test suite covering business logic, data transformations, and integration points.

**How to verify**:
- Unit tests for business logic functions (pure logic, calculations, transformations)
- Integration tests for API endpoints (request/response, auth, validation)
- Integration tests for database operations (CRUD, migrations, constraints)
- Coverage target: >60% on business logic files, >80% on auth/security files
- Check that tests actually assert things (not just "it doesn't crash")

### 3.3 Security and E2E Tests `[public]`

**What to check**: Security-specific tests and end-to-end tests for primary flows.

**How to verify**:
- Auth tests: login with invalid credentials fails, expired tokens are rejected, CSRF protection works
- Authorization tests: users cannot access other users' resources, role restrictions are enforced
- Input validation tests: SQL injection attempts are rejected, XSS payloads are sanitized
- E2E tests: primary user flows work end-to-end in a browser-like environment
- Check for regression tests on previously found security issues

---

## 4. Security

### 4.1 Basic Security `[mvp]`

**What to check**: No committed secrets. Basic authentication if the app has any protected features.

**How to verify**:
- Secret scan passes
- If auth exists: passwords are hashed (not plaintext), sessions have expiry
- HTTPS used for any external API calls with credentials

### 4.2 OWASP Top 10 Review `[production]`

**What to check**: The application has been reviewed against the OWASP Top 10.

**How to verify**:
- A01: Broken Access Control -- authorization checks on all endpoints
- A02: Cryptographic Failures -- proper encryption, no weak algorithms
- A03: Injection -- parameterized queries, output encoding
- A04: Insecure Design -- threat model considered
- A05: Security Misconfiguration -- security headers, default credentials changed
- A06: Vulnerable Components -- dependency audit clean
- A07: Auth Failures -- rate limiting, strong passwords, MFA option
- A08: Data Integrity Failures -- input validation, signed data
- A09: Logging Failures -- security events logged
- A10: SSRF -- server-side requests validated

### 4.3 Dependency Audit `[production]`

**What to check**: No dependencies with known exploitable vulnerabilities.

**How to verify**:
- Run `npm audit`, `pip-audit`, `cargo audit`, `govulncheck`, or equivalent
- Resolve HIGH and CRITICAL findings
- Document any accepted risks (vulnerability not exploitable in this context)

### 4.4 CSP and Security Headers `[production]`

**What to check**: Security headers are configured and appropriate.

**How to verify**:
- Content-Security-Policy is present and restrictive
- Strict-Transport-Security is present with `max-age >= 31536000`
- X-Content-Type-Options is `nosniff`
- X-Frame-Options is `DENY` or `SAMEORIGIN`
- Referrer-Policy is configured

### 4.5 Supply Chain and Penetration Testing `[public]`

**What to check**: Supply chain has been audited and penetration testing has been considered.

**How to verify**:
- All dependencies have been reviewed for provenance
- SRI hashes on third-party scripts
- CI/CD pipeline uses pinned actions/dependencies
- Penetration test scheduled or completed (for applications handling sensitive data)
- `security.txt` at `/.well-known/security.txt` with vulnerability reporting process

---

## 5. Logging and Observability

### 5.1 Structured Logging `[production]`

**What to check**: Logging uses a structured format (JSON) with consistent fields.

**How to verify**:
- Find logging configuration: `winston`, `pino`, `logging.config`, `logrus`, `slog`
- Check log format: should be JSON or structured, not `console.log` with string concatenation
- Check for consistent fields: timestamp, level, message, request ID, user ID (without PII)
- Check that sensitive data is NOT logged (passwords, tokens, PII)

### 5.2 Error Tracking `[production]`

**What to check**: Unhandled errors are captured and reported to an error tracking service.

**How to verify**:
- Check for error tracking integration: Sentry, Bugsnag, Rollbar, Datadog, etc.
- Verify it captures: unhandled exceptions, unhandled promise rejections, framework-level errors
- Check that source maps are uploaded (for minified code)
- Check that PII is scrubbed from error reports

### 5.3 Health Check Endpoint `[production]`

**What to check**: A health check endpoint exists for load balancers and monitoring.

**How to verify**:
- Find `/health`, `/healthz`, `/ready`, `/status` endpoint
- Check that it verifies critical dependencies (database connection, cache connection)
- Check that it returns appropriate HTTP status codes (200 for healthy, 503 for unhealthy)
- Check that it doesn't require authentication (load balancers need to access it)

### 5.4 Performance Monitoring `[production]`

**What to check**: Application performance is monitored.

**How to verify**:
- Check for APM integration or custom metrics
- Request duration is tracked
- Database query performance is tracked
- External API call latency is tracked

---

## 6. Operations

### 6.1 Deployment Documented `[production]`

**What to check**: Deployment process is documented and repeatable.

**How to verify**:
- Deployment steps are written down (README, DEPLOYMENT.md, runbook)
- Steps include: how to deploy, how to verify deployment, who to contact if it fails
- Check for infrastructure-as-code: Terraform, Pulumi, CloudFormation, Docker Compose, Kubernetes manifests

### 6.2 Rollback Procedure `[production]`

**What to check**: There is a documented way to roll back a bad deployment.

**How to verify**:
- Rollback steps are documented
- Rollback has been tested (at least theoretically)
- Database migrations are backward-compatible (or rollback includes migration reversal)

### 6.3 Database Migration Strategy `[production]`

**What to check**: Database schema changes are managed through migrations, not manual DDL.

**How to verify**:
- Check for migration tool: Knex migrations, Alembic, Flyway, Entity Framework migrations, Prisma migrate
- Migrations are committed and version-controlled
- Migrations are idempotent or have rollback counterparts
- Check for destructive migrations: column drops, table drops should be staged (rename first, drop later)

### 6.4 Backup Strategy `[production]`

**What to check**: Data that matters is backed up and backups are tested.

**How to verify**:
- Check for backup configuration in infrastructure code or documentation
- Verify backups are automated (not manual)
- Verify backup restoration has been tested at least once
- Check that backups are encrypted if they contain sensitive data

### 6.5 Monitoring and Alerting `[production]`

**What to check**: Alerts are configured for critical failure conditions.

**How to verify**:
- Check for alerting configuration: PagerDuty, OpsGenie, Slack webhooks, CloudWatch alarms
- Alerts should cover: application down, high error rate, high latency, disk space, certificate expiry
- Check that alerts go to a monitored channel (not a dead email alias)

---

## 7. Documentation

### 7.1 README with Setup Instructions `[mvp]`

**What to check**: A README exists with enough information for a new developer to set up and run the project.

**How to verify**:
- README exists at project root
- Contains: what the project is, how to install dependencies, how to run locally, how to run tests
- Setup instructions actually work (dependencies are listed, commands are correct)

### 7.2 Architecture Overview `[production]`

**What to check**: High-level architecture is documented.

**How to verify**:
- Document describes: main components, how they communicate, external dependencies, data flow
- Doesn't need to be elaborate -- a diagram and a few paragraphs is sufficient
- Should cover: where auth happens, where data is stored, what external services are called

### 7.3 API Documentation `[production]`

**What to check**: API endpoints are documented with request/response formats.

**How to verify**:
- Check for API docs: OpenAPI/Swagger spec, Postman collection, or equivalent
- Each endpoint: method, path, request body schema, response schema, auth requirements, error responses
- Docs are in sync with actual implementation (or auto-generated from code)

### 7.4 Environment Variable Documentation `[production]`

**What to check**: All environment variables are documented with descriptions and example values.

**How to verify**:
- Cross-reference code env var usage with documentation
- Each variable: name, description, required/optional, type, default value, example

### 7.5 Full Documentation Suite `[public]`

**What to check**: Complete documentation for external contributors and users.

**How to verify**:
- Everything from production level, plus:
- Contributing guide (how to submit PRs, coding standards, review process)
- Code of conduct
- Changelog or release notes
- User-facing documentation (if applicable)

---

## 8. Open Source Readiness

*All items in this section are `[public]` only.*

### 8.1 LICENSE File

**What to check**: A LICENSE file exists at project root with a recognized open source license.

**How to verify**:
- File exists: `LICENSE`, `LICENSE.md`, or `LICENSE.txt`
- License is a recognized SPDX identifier (MIT, Apache-2.0, GPL-3.0, etc.)
- License year and copyright holder are correct
- `license` field in `package.json` / `pyproject.toml` / `Cargo.toml` matches the LICENSE file

**Release gate**: Hard block. No LICENSE file means the code is not legally open source.

### 8.2 CONTRIBUTING.md

**What to check**: A contributing guide exists explaining how to contribute.

**How to verify**:
- File exists at project root
- Contains: how to report bugs, how to request features, how to submit PRs, coding standards, testing requirements, review process

### 8.3 CODE_OF_CONDUCT.md

**What to check**: A code of conduct exists.

**How to verify**:
- File exists at project root
- Uses a recognized code of conduct (Contributor Covenant is most common)
- Includes enforcement contact information

### 8.4 SECURITY.md

**What to check**: A security policy exists explaining how to report vulnerabilities.

**How to verify**:
- File exists at project root or `/.github/SECURITY.md`
- Includes: how to report (email, not public issue), expected response time, scope
- Does NOT say "file a GitHub issue" for security vulnerabilities (public disclosure)

### 8.5 No Proprietary Content

**What to check**: No proprietary dependencies, internal references, or confidential information.

**How to verify**:
- Search for internal hostnames, internal domain names, internal service names
- Search for employee names, email addresses, Slack channel names
- Search for proprietary package registries or private npm scopes
- Check for internal documentation references, wiki links, or Jira ticket numbers
- Verify all dependencies have OSS-compatible licenses

### 8.6 Dependency License Compatibility

**What to check**: All dependency licenses are compatible with the project's license.

**How to verify**:
- Run license checker: `license-checker` (npm), `pip-licenses` (Python), `cargo-license` (Rust)
- Identify incompatible licenses: GPL dependencies in MIT projects (if not desired), AGPL in proprietary projects
- Check for dependencies with no license (legally cannot be used)
- Check for dependencies with restrictive licenses (SSPL, BSL, Commons Clause)

**Release gate**: Incompatible licenses are a legal blocker.

---

## Release Decision Matrix

| Item | mvp | production | public |
|---|---|---|---|
| Committed secrets | BLOCKS | BLOCKS | BLOCKS |
| Critical security finding | BLOCKS | BLOCKS | BLOCKS |
| Major security finding | Recommend | BLOCKS | BLOCKS |
| Moderate security finding | Info | Recommend | BLOCKS |
| .env.example exists | Required | Required | Required |
| CI pipeline | - | Required | Required |
| Test coverage (critical paths) | Required | Required | Required |
| Test coverage (comprehensive) | - | Required | Required |
| Security tests | - | - | Required |
| Health check endpoint | - | Required | Required |
| Error tracking | - | Required | Required |
| Deployment docs | - | Required | Required |
| Rollback procedure | - | Required | Required |
| LICENSE file | - | - | BLOCKS |
| SECURITY.md | - | - | Required |
| License compatibility | - | - | BLOCKS |
| No internal references | - | - | BLOCKS |
