# Trust Model and Review Depth Policy

This document defines the trust levels applied to different types of code and artifacts during a UCR review. Trust level determines review depth, evidence requirements, and which checklists are applied.

---

## Trust Levels

### Untrusted (Full Review)

**Applies to**: All user-written code, AI-generated code, custom configuration, build scripts, CI/CD configs, Dockerfiles, infrastructure-as-code templates, database migrations, and any file that could affect application behavior, security, or data integrity.

**Review depth**: Every line. No skipping. No assumptions of correctness.

**Specific file types**:

| File Type | Why Untrusted | What to Check |
|---|---|---|
| Application source code (`.js`, `.ts`, `.py`, `.go`, `.rs`, `.java`, etc.) | Core logic, all bugs live here | All checklists: security, functional, performance, code quality, AI slop |
| Configuration files (`config.js`, `settings.py`, `application.yml`, `appsettings.json`) | Controls application behavior, may contain secrets | Secrets, correctness, environment separation |
| Build scripts (`webpack.config.js`, `vite.config.ts`, `Makefile`, `build.gradle`) | Affects build output, can execute arbitrary code | Correctness, no secret exposure, no external fetches during build |
| CI/CD configs (`.github/workflows/*.yml`, `Jenkinsfile`, `.gitlab-ci.yml`) | Runs in privileged environments, handles secrets | Secret exposure in logs, pinned action versions, minimal permissions |
| Dockerfiles | Defines runtime environment, can introduce vulnerabilities | Base image version pinned, no secrets in build args, minimal image, non-root user |
| IaC templates (Terraform, CloudFormation, Pulumi) | Controls infrastructure, can expose services to the internet | Security groups, public access, encryption settings, IAM permissions |
| Database migrations | Irreversible changes to data schema | Backward compatibility, data preservation, rollback support |
| Environment files (`.env`, `.env.example`) | May contain secrets | Secrets check, placeholder values in example files |
| Test files | Tests define expected behavior, test utilities may be used in production | Test correctness, no real secrets in test fixtures, test utility safety |

**Evidence requirements**: Maximum. Every finding must reference specific file, line number, and code. Confidence levels must be stated.

**Checklists applied**: All applicable checklists (security, UX/accessibility, release readiness, AI slop detection).

---

### Semi-Trusted (Review Usage, Not Internals)

**Applies to**: Well-known framework code, standard library usage, typed SDK wrappers, established open-source library APIs.

**Review depth**: Review HOW the code uses these libraries, not the library internals. Assume the library works correctly, but do not assume it is used correctly.

**Specific examples**:

| What | Trust Level | What to Check |
|---|---|---|
| Express/Fastify/Koa route setup | Semi-trusted | Correct middleware order, proper error handler, correct route patterns |
| React/Vue/Svelte component lifecycle | Semi-trusted | Correct hook usage, proper effect cleanup, correct dependency arrays |
| ORM queries (Prisma, Sequelize, SQLAlchemy, GORM) | Semi-trusted | Query correctness, N+1 detection, raw query safety, migration correctness |
| Auth libraries (Passport, NextAuth, django-allauth) | Semi-trusted | Correct configuration, proper callback handling, session settings |
| HTTP clients (axios, fetch, requests) | Semi-trusted | Timeout configuration, error handling, auth header handling |
| Logging libraries (winston, pino, logging, slog) | Semi-trusted | Sensitive data not logged, log level configuration, structured format |
| Validation libraries (zod, joi, yup, pydantic) | Semi-trusted | Schema correctness, applied at trust boundaries, error handling |

**What specifically to check**:

1. **Correct usage patterns**: Is the library being used as its documentation prescribes? Common mistakes:
   - Express middleware in wrong order (error handler must be last)
   - React hooks called conditionally (violates rules of hooks)
   - ORM queries that bypass built-in sanitization (`.raw()`, `.literal()`)
   - Auth library configured with weak defaults not overridden

2. **Misconfiguration**: Is the library configured securely and correctly?
   - Session cookies without `secure: true`
   - CORS with wildcard origin
   - JWT verification without algorithm specification
   - Logging configured to include request bodies (may contain passwords)

3. **Version compatibility**: Is the code compatible with the installed version?
   - Deprecated API usage for the installed version
   - APIs that changed behavior between versions
   - Missing required configuration added in newer versions

**Evidence requirements**: Must reference the library documentation or known best practices when flagging incorrect usage. Must specify the installed version when flagging version-specific issues.

**Checklists applied**: Security checklist (for configuration), AI slop (for cargo-cult patterns and deprecated APIs). Not: internal code quality of the library.

---

### Excluded (Skip, But Audit Versions)

**Applies to**: Dependency directories, generated files, compiled output, build artifacts, version control metadata.

**Review depth**: Do NOT review file contents. DO audit metadata.

**Specific directories and files**:

| Path | Why Excluded | What to Audit |
|---|---|---|
| `node_modules/` | Third-party packages, too large to review | Package versions via lockfile, known CVEs, license compliance |
| `vendor/` (Go, PHP, Ruby) | Vendored dependencies | Package versions, known CVEs, license compliance |
| `venv/`, `.venv/`, `env/` | Python virtual environments | Not audited (local dev only) |
| `dist/`, `build/`, `out/`, `.next/` | Compiled/bundled output | Not audited (generated from source) |
| `coverage/`, `.nyc_output/` | Test coverage reports | Not audited |
| `.git/` | Version control metadata | Not audited |
| `*.min.js`, `*.min.css` | Minified files | Should match source, verify SRI if served from CDN |
| `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` | Generated lockfiles | Audit for integrity, check for unexpected registry changes |
| `*.map` | Source maps | Should not be deployed to production (information disclosure) |

**What specifically to audit**:

1. **Package versions**: Cross-reference lockfile against known CVE databases. Flag packages with HIGH or CRITICAL CVEs.
2. **License compliance**: Check dependency licenses are compatible with the project license. Flag unknown or restrictive licenses.
3. **Unexpected files**: Flag files that should not be in these directories:
   - `.env` files inside `node_modules/` (could indicate a compromised package)
   - Executable files (`.exe`, `.sh`, `.bat`) in unexpected locations
   - Source code files in `dist/` that aren't part of the build output
4. **Registry integrity**: Check lockfile for unexpected registry changes (all packages should come from the expected registry).
5. **Lockfile changes**: If the lockfile was modified in this PR, verify the changes are intentional and match dependency manifest changes.

**Checklists applied**: Dependency security (CVEs, licenses) only.

---

### Secrets-Sensitive (Flag, Never Display)

**Applies to**: Any file that could contain secrets. These files get a special review mode: the reviewer checks for secret presence but NEVER displays secret values in findings.

**Specific files**:

| File Pattern | Common Secrets |
|---|---|
| `.env`, `.env.local`, `.env.production`, `.env.staging` | API keys, database URLs, secret keys |
| `credentials.json`, `service-account-key.json` | GCP service account keys |
| `*.pem`, `*.key`, `*.p12`, `*.pfx` | TLS/SSL private keys, certificates |
| `config.json`, `config.yml` with connection strings | Database passwords, API tokens |
| `docker-compose.yml` with environment variables | Inline secrets in compose files |
| `.npmrc`, `.pypirc`, `pip.conf` with auth tokens | Package registry credentials |
| CI/CD variable references (`${{ secrets.* }}`, `$VARIABLE`) | Usually safe (references), but check for inline values |
| `terraform.tfvars`, `*.auto.tfvars` | Infrastructure secrets |
| `kubeconfig`, `kube/config` | Kubernetes cluster credentials |

**Review protocol for secrets-sensitive files**:

1. DETERMINE if the file contains actual secret values (not just references or placeholders)
2. If actual secrets are found:
   - Report: file path, line number, key/variable NAME, secret TYPE (API key, password, private key, etc.)
   - NEVER report: the actual secret value, even partially. No first/last characters. No length hints. No "looks like a JWT."
   - In code snippets: replace the value entirely: `API_KEY=<REDACTED_API_KEY>`
   - Severity: always Critical
   - Recommendation: rotate the secret immediately, remove from repository, use environment injection
3. If references or placeholders are found:
   - Report as informational: "File contains environment variable references, no actual secrets detected"
4. Mask completely in ALL output -- findings, summaries, code snippets, recommendations

**What constitutes an "actual secret"**:
- A string that looks like a real credential: high-entropy base64, hex strings, strings starting with known prefixes (`sk_live_`, `AKIA`, `ghp_`, `xoxb-`, `-----BEGIN`)
- Connection strings with embedded credentials: `postgres://user:password@host/db`
- Private key material (PEM format content)
- Long random-looking strings assigned to variables named `key`, `secret`, `token`, `password`, `credential`, `api_key`

**What is NOT an actual secret**:
- `process.env.API_KEY` (reference, not value)
- `API_KEY=changeme` or `API_KEY=your-key-here` (placeholder)
- `API_KEY=${{ secrets.API_KEY }}` (CI/CD reference)
- `API_KEY=` (empty value)

---

## Trust Boundaries

A trust boundary exists wherever data crosses between different trust levels. Every trust boundary must be reviewed for proper validation, sanitization, and error handling.

### Identifying Trust Boundaries

| Boundary | From (Untrusted) | To (Application Code) | What to Check |
|---|---|---|---|
| HTTP request | User/client | API handler | Input validation, authentication, authorization, CSRF |
| Form submission | User browser | Server handler | Input validation, CSRF token, file upload validation |
| API response | External service | Application | Response validation, error handling, timeout, type checking |
| Database read | Database | Application | Null handling, type coercion, missing field handling |
| File system read | File system | Application | Existence check, permission check, format validation, path traversal |
| Environment variable | Runtime environment | Application | Presence check, format validation, default values |
| Message queue | Other service | Consumer | Message format validation, idempotency, dead letter handling |
| Webhook | External service | Webhook handler | Signature verification, replay protection, payload validation |
| User upload | User file | Application | File type validation (magic bytes), size limits, antivirus, sanitization |
| OAuth callback | OAuth provider | Application | State parameter validation, token exchange, scope verification |
| LLM response | AI model | Application | Output validation, sanitization before rendering, no direct execution |

### Trust Boundary Review Checklist

For EVERY identified trust boundary, check:

1. **Input validation**: Is data validated at the boundary? Type, format, length, range, required fields.
2. **Sanitization**: Is data sanitized before use? HTML encoding, SQL parameterization, path normalization.
3. **Error handling**: What happens when the external side sends unexpected data? Null, wrong type, malformed, oversized.
4. **Authentication**: Is the source verified? API keys, signatures, certificates, tokens.
5. **Authorization**: Even if authenticated, is this source allowed to send this specific data?
6. **Rate limiting**: Can the external side overwhelm the application?
7. **Logging**: Are boundary crossings logged (without sensitive data)?

---

## Handling Code That Straddles Trust Levels

Some code interacts with both trusted and untrusted inputs. Rules for these cases:

### Principle: Apply the Strictest Trust Level

If a function receives user input (untrusted) and passes it to a framework method (semi-trusted), the FUNCTION is reviewed at the untrusted level. The trust level of the most untrusted input determines the review depth for the entire code path.

### Examples

**ORM with raw queries**:
```javascript
// Semi-trusted: ORM query with builder
const users = await User.findAll({ where: { status: 'active' } });

// Untrusted: Raw query with user input in the same file
const results = await sequelize.query(`SELECT * FROM users WHERE name LIKE '%${search}%'`);
```
The file contains both semi-trusted ORM usage and untrusted raw SQL. The raw SQL must be reviewed at the untrusted level. The ORM usage is reviewed at semi-trusted level. The finding should note that the mixing of patterns is itself a concern (inconsistency).

**Framework middleware with custom logic**:
```python
# Semi-trusted: Flask route decorator
@app.route('/api/users/<int:user_id>')
@login_required  # Semi-trusted: Flask-Login decorator
def get_user(user_id):
    # Untrusted: Custom authorization logic
    user = User.query.get(user_id)
    if user.tenant_id != current_user.tenant_id:
        abort(403)
    return jsonify(user.to_dict())
```
The route setup and auth decorator are semi-trusted. The custom authorization logic (tenant check) is untrusted and reviewed at full depth.

---

## Interaction with .ucrconfig.yml Exclusions

The `.ucrconfig.yml` configuration may specify files or directories to exclude from review. These exclusions interact with trust levels as follows:

### Exclusion Rules

1. **Excluded directories in config** (e.g., `exclude: [vendor/, docs/]`): Files in these directories are skipped entirely. They are not even audited for versions/CVEs unless the directory is a dependency directory.

2. **Config exclusions CANNOT override secrets-sensitive review**: Even if a file pattern is in the exclude list, if it matches a secrets-sensitive pattern (`.env`, `credentials.json`, `*.key`), it MUST still be checked for secrets. Secret detection is never excludable.

3. **Config exclusions CANNOT exclude trust boundary files**: If an excluded file is referenced at a trust boundary (e.g., a config file loaded by the application), it should be flagged as a potential blind spot. The reviewer notes: "File X is excluded from review but is loaded by application code at Y:Z. Consider removing from exclusions."

4. **Config exclusions of untrusted code are flagged**: If application source code is in the exclude list, the reviewer must note this in the report: "The following source files are excluded from review by configuration: [list]. This reduces review coverage. Excluded source files are not reflected in the confidence assessment."

### Trust Level Cannot Be Reduced by Configuration

Configuration can exclude files from review (skip entirely), but it cannot change a file's trust level. There is no way to mark user-written code as "semi-trusted" or "excluded" via configuration. The trust level is determined by the file's nature, not by project settings.

### Recommended Exclusions

Files that are safe to exclude and reduce review noise:

```yaml
exclude:
  - "*.test.js"           # Test files (unless reviewing test quality)
  - "*.spec.ts"           # Test files
  - "__tests__/"           # Test directories
  - "*.stories.tsx"        # Storybook stories
  - "docs/"                # Documentation
  - "*.md"                 # Markdown files
  - "migrations/"          # Only if migrations are auto-generated and not hand-edited
```

Files that should NOT be excluded:

```yaml
# NEVER exclude these:
# - .env* files (secrets-sensitive)
# - Configuration files (trust boundary)
# - CI/CD configurations (privileged execution context)
# - Dockerfiles (runtime environment definition)
# - Build scripts (executed in CI/CD)
# - Database migration files if hand-written
```
