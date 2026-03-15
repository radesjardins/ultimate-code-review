# Security Review Checklist

This document provides the complete security checklist used by UCR security review agents. For each item: what to check, how to find it in code, the severity when violated, and common AI-generated mistakes to watch for.

---

## 1. Authentication

### 1.1 Password Storage

**What to check**: Passwords must be hashed with bcrypt, argon2, or scrypt. Never MD5, SHA1, SHA256, or any unsalted hash. Never plaintext.

**How to check in code**:
- Search for password-related functions: `hash`, `password`, `credential`, `bcrypt`, `argon2`, `scrypt`
- Search for weak hashing: `md5`, `sha1`, `sha256`, `createHash`, `hashlib.md5`, `MessageDigest`
- Search for plaintext storage: database schemas where password column is VARCHAR without a hash prefix ($2b$, $argon2id$)
- Check password comparison: must use constant-time comparison (`bcrypt.compare`, `argon2.verify`), never `===` or `==`

**Severity**: Critical if plaintext or weak hash. Major if timing-unsafe comparison.

**Common AI mistakes**: Using SHA256 for passwords (it's fast, not suitable for passwords). Using bcrypt with a cost factor below 10. Storing the salt separately (bcrypt includes it in the hash). Using `crypto.createHash('sha256')` instead of `bcrypt.hash`.

### 1.2 Session Management

**What to check**: Sessions must have server-side state or use signed/encrypted tokens. Session IDs must be cryptographically random. Sessions must expire. Session fixation must be prevented.

**How to check in code**:
- Find session configuration: `session`, `cookie`, `express-session`, `SessionMiddleware`
- Verify session secret is from environment variable, not hardcoded
- Check cookie flags: `httpOnly: true`, `secure: true`, `sameSite: 'strict'` or `'lax'`
- Check session expiry: `maxAge`, `expires`, `SESSION_LIFETIME`
- Verify session regeneration on login (prevent fixation): `req.session.regenerate`

**Severity**: Major if session IDs are predictable. Major if cookies lack HttpOnly/Secure. Moderate if SameSite is not set.

**Common AI mistakes**: Hardcoded session secret (`secret: 'keyboard cat'`). Missing `secure: true` (works in dev over HTTP, fails silently in prod). No session expiry. No session regeneration after login.

### 1.3 Token Handling (JWT)

**What to check**: JWTs must use strong algorithms (RS256, ES256, or HS256 with 256-bit+ secret). Algorithm must be validated server-side. Tokens must have expiry. Refresh token rotation must be implemented.

**How to check in code**:
- Find JWT usage: `jsonwebtoken`, `jwt`, `jose`, `PyJWT`
- Check algorithm: `algorithms: ['HS256']` in verify options (MUST be specified, not left as default)
- Check secret strength: must be from environment, at least 32 bytes for HMAC
- Check expiry: `expiresIn` on sign, `exp` claim verified
- Check `none` algorithm rejection: `algorithms` parameter must be explicitly set in verify

**Severity**: Critical if algorithm is `none` or not validated. Critical if secret is hardcoded. Major if no expiry. Major if algorithm is specified only on sign, not on verify (algorithm confusion attack).

**Common AI mistakes**: `jwt.verify(token, secret)` without specifying algorithms (allows algorithm confusion). Hardcoded JWT secret. Token expiry set to very long period (30d+). No refresh token mechanism. Storing JWT in localStorage (XSS accessible).

### 1.4 MFA Support

**What to check**: If MFA is implemented, verify TOTP parameters, backup codes, and enrollment flow.

**How to check in code**:
- TOTP secret must be generated with sufficient entropy (20+ bytes)
- TOTP window should be narrow (1-2 periods max)
- Backup codes must be single-use, hashed, and limited in count
- MFA bypass must not be possible by hitting the pre-MFA auth endpoint directly

**Severity**: Major if MFA can be bypassed. Moderate if TOTP window is too wide.

### 1.5 Account Lockout

**What to check**: Brute-force protection on login, password reset, and MFA verification endpoints.

**How to check in code**:
- Rate limiting on `/login`, `/auth`, `/reset-password`, `/verify-mfa`
- Account lockout after N failed attempts (5-10 typical)
- Lockout duration increases with repeated failures
- Lockout state stored server-side (not in a client cookie)

**Severity**: Major if no rate limiting on auth endpoints. Moderate if lockout is too permissive (>20 attempts).

**Common AI mistakes**: Rate limiting by IP only (easily bypassed with distributed attacks). No rate limiting at all. Lockout that never resets (permanent denial of service).

### 1.6 Password Reset Flow

**What to check**: Reset tokens must be cryptographically random, single-use, time-limited, and invalidated on password change.

**How to check in code**:
- Token generation: `crypto.randomBytes(32)` or equivalent, not `Math.random()`
- Token storage: hashed in database, not plaintext
- Token expiry: 15-60 minutes typical
- Token invalidation: all tokens invalidated when password is changed
- No user enumeration: same response for valid and invalid emails

**Severity**: Critical if tokens are predictable. Major if tokens don't expire. Major if user enumeration is possible.

### 1.7 OAuth Implementation

**What to check**: State parameter for CSRF protection, PKCE for public clients, token storage security, scope minimization.

**How to check in code**:
- `state` parameter generated, stored in session, and validated on callback
- PKCE (`code_verifier`, `code_challenge`) for SPAs and mobile apps
- Access tokens not stored in localStorage
- Redirect URI validated against allowlist (not just prefix match)
- Scopes requested are minimal

**Severity**: Critical if state parameter is missing (CSRF on OAuth flow). Major if redirect URI validation is weak.

---

## 2. Authorization

### 2.1 RBAC/ABAC Implementation

**What to check**: Role checks are centralized, not duplicated. Roles are checked server-side, not just in the UI. Default is deny, not allow.

**How to check in code**:
- Find authorization middleware/decorators: `authorize`, `requireRole`, `@permission_required`, `can()`, `ability`
- Verify all state-changing API endpoints have authorization checks
- Check that admin functions check for admin role, not just authentication
- Verify roles come from server-side session/token, not from request body or URL parameters

**Severity**: Critical if authorization is client-side only. Major if some endpoints are missing authorization.

**Common AI mistakes**: Checking `req.body.role === 'admin'` (user-supplied). Checking roles in UI but not in API handler. Authorization check present in the route definition but the middleware function is a no-op.

### 2.2 IDOR (Insecure Direct Object Reference)

**What to check**: When a user requests a resource by ID, verify the user has permission to access that specific resource.

**How to check in code**:
- Find endpoints with path parameters: `/users/:id`, `/orders/:orderId`, `/files/:fileId`
- For each: verify the handler checks that the requested resource belongs to the authenticated user
- Check for tenant isolation in multi-tenant apps: queries must include tenant filter
- Sequential/predictable IDs increase IDOR risk (UUIDs reduce it but don't eliminate it)

**Severity**: Major. Broken access control is OWASP #1.

**Common AI mistakes**: `Model.findById(req.params.id)` without checking ownership. Admin endpoints that accept user ID from the URL without verifying the requester is an admin. Tenant ID taken from the request instead of from the authenticated session.

### 2.3 Default-Deny Policy

**What to check**: Access is denied by default. Routes require explicit opt-in to be public.

**How to check in code**:
- Is there global authentication middleware that runs before route handlers?
- Are public routes explicitly marked (e.g., `@public`, `skipAuth`, allowlist)?
- Or is auth middleware applied per-route (error-prone, easy to forget)?

**Severity**: Major if the default is open and auth is applied per-route (missing one route = unauthenticated access).

---

## 3. Injection

### 3.1 SQL Injection

**What to check**: All SQL queries use parameterized queries or an ORM. No string concatenation of user input into SQL.

**How to check in code**:
- Search for string concatenation in SQL: `` `SELECT...${` ``, `"SELECT..." + `, `f"SELECT...{`, `"SELECT...%s" %`, `.format(` near SQL keywords
- Search for raw query methods: `db.raw()`, `connection.execute()`, `cursor.execute()` -- verify parameters are passed separately
- ORM raw query escape hatches: `Sequelize.literal()`, `knex.raw()`, `RawSQL()`

**Severity**: Critical. SQL injection enables full database access, data exfiltration, and potentially RCE.

**Common AI mistakes**: Using template literals for SQL: `` db.query(`SELECT * FROM users WHERE id = ${userId}`) ``. Using `.format()` in Python: `cursor.execute(f"SELECT * FROM users WHERE email = '{email}'")`. ORM queries that fall back to raw SQL for complex queries without parameterization.

### 3.2 XSS (Cross-Site Scripting)

**What to check**: All user-supplied data rendered in HTML is escaped. CSP headers are configured. innerHTML / dangerouslySetInnerHTML usage is justified and sanitized.

**How to check in code**:
- Search for dangerous rendering: `innerHTML`, `dangerouslySetInnerHTML`, `document.write`, `v-html`, `[innerHTML]`, `{!! !!}` (Blade), `|safe` (Jinja2)
- For each instance: trace the data source. If it's user input, it must be sanitized (DOMPurify, sanitize-html, bleach)
- Check CSP headers: `Content-Security-Policy` with restricted `script-src`
- Check for reflected XSS: user input from URL parameters rendered directly into the page

**Severity**: Major for stored XSS. Major for reflected XSS on pages with sensitive data. Moderate for reflected XSS on public pages.

**Common AI mistakes**: Using `dangerouslySetInnerHTML` for markdown rendering without sanitization. Trusting data from the database (it was user input when it went in). Missing CSP headers entirely. CSP with `'unsafe-inline'` (defeats the purpose).

### 3.3 CSRF (Cross-Site Request Forgery)

**What to check**: State-changing requests (POST, PUT, DELETE) require a CSRF token or use SameSite cookie attribute.

**How to check in code**:
- Find CSRF middleware: `csrf()`, `csurf`, `@csrf_protect`, `AntiForgeryToken`
- Verify it's applied to all state-changing endpoints
- Check cookie `SameSite` attribute: `Strict` or `Lax`
- For SPAs: verify the token is sent in a custom header (not a cookie-only approach)

**Severity**: Major on state-changing operations with user data. Moderate on non-sensitive state changes.

### 3.4 SSRF (Server-Side Request Forgery)

**What to check**: Any endpoint that fetches a URL provided by the user must validate the URL against an allowlist and block internal network access.

**How to check in code**:
- Find server-side fetch/request with user-controlled URLs: `fetch(req.body.url)`, `requests.get(url)`, `http.get(url)`
- Verify URL validation: protocol allowlist (https only), hostname allowlist, no private IP ranges (10.x, 172.16-31.x, 192.168.x, 127.x, 169.254.x, ::1, fc00::/7)
- Check for DNS rebinding: validate IP after DNS resolution, not just the hostname
- Check for redirect following: disable or validate redirected URLs too

**Severity**: Critical if internal network is accessible. Major if only external sites are accessible.

### 3.5 Command Injection

**What to check**: User input never passed to shell commands. If shell interaction is necessary, use array-based execution (not string commands).

**How to check in code**:
- Search for: `exec(`, `execSync(`, `child_process`, `os.system(`, `subprocess.call(`, `subprocess.Popen(`, `Runtime.exec(`
- For each: check if any argument contains user input
- Verify shell option is false: `{ shell: false }` in Node.js, `shell=False` in Python
- Prefer `execFile` / `spawn` (array args) over `exec` (string command)

**Severity**: Critical. Command injection enables RCE.

### 3.6 Path Traversal

**What to check**: User-supplied file paths are validated to prevent accessing files outside the intended directory.

**How to check in code**:
- Find file operations with user-controlled paths: `fs.readFile(req.params.filename)`, `open(user_input)`, `send_file()`
- Verify path is resolved and checked: `path.resolve()` + starts-with check against allowed directory
- Check for `../` in user input, URL-encoded `..%2f`, null bytes `%00`

**Severity**: Critical if sensitive files (`.env`, `/etc/passwd`, database files) are readable. Major if file listing is exposed.

### 3.7 Template Injection

**What to check**: User input not passed as template code (only as template data/context).

**How to check in code**:
- Search for template rendering with user-controlled template strings: `Jinja2(userInput)`, `new Function(userInput)`, `eval()`, `ejs.render(userInput)`
- Verify: user data goes into template context (safe), not into the template string (unsafe)

**Severity**: Critical. Template injection often leads to RCE.

### 3.8 Header Injection

**What to check**: User input is not included in HTTP response headers without validation.

**How to check in code**:
- Search for: `res.setHeader()`, `response.headers[]`, `header()` where the value includes user input
- Check for newline characters in user input (enables header splitting)
- Verify `Location` header (redirects) doesn't include unvalidated user input

**Severity**: Major if exploitable for response splitting or cache poisoning.

---

## 4. Data Protection

### 4.1 Encryption at Rest

**What to check**: Sensitive data in databases, files, and backups is encrypted.

**How to check in code**:
- Database fields containing PII, financial data, or health data should use encryption (application-level or database-level)
- Check for field-level encryption libraries: `node-forge`, `cryptography` (Python), `javax.crypto`
- Backup scripts should encrypt output
- SQLite databases with sensitive data should use SQLCipher or equivalent

**Severity**: Major if PII is stored unencrypted. Critical if financial/health data is unencrypted (may violate PCI-DSS, HIPAA).

### 4.2 Encryption in Transit

**What to check**: All external communication uses TLS. No HTTP fallback. Certificate validation is not disabled.

**How to check in code**:
- Search for: `http://` (should be `https://` for external services), `rejectUnauthorized: false`, `verify=False`, `InsecureRequestWarning`, `CURLOPT_SSL_VERIFYPEER`
- Check webhook endpoints: must use HTTPS
- Check internal service communication: should use TLS or be within a secure network

**Severity**: Critical if credentials are sent over HTTP. Major if PII is sent over HTTP. Moderate for non-sensitive data.

**Common AI mistakes**: `rejectUnauthorized: false` to "fix" certificate errors in development, left in production. `verify=False` in Python requests. HTTP URLs for API endpoints because the tutorial used HTTP.

### 4.3 Sensitive Data in Logs

**What to check**: Logs must not contain passwords, tokens, API keys, credit card numbers, SSNs, or other PII.

**How to check in code**:
- Find logging statements: `console.log`, `logger.info`, `logging.debug`, `Log.d`
- Check if they log request bodies (may contain passwords), headers (may contain auth tokens), or full error objects (may contain sensitive context)
- Check for structured logging that automatically serializes objects (may include sensitive fields)

**Severity**: Major if passwords or tokens are logged. Moderate if PII is logged.

**Common AI mistakes**: `console.log('Request:', req.body)` which logs everything including passwords. `logger.error('Auth failed', { error, user })` which may serialize the user object including password hash. Logging full HTTP headers including Authorization.

### 4.4 PII Handling

**What to check**: PII is identified, minimized, and protected throughout the application lifecycle.

**How to check in code**:
- Identify PII fields: email, phone, address, SSN, date of birth, IP address, geolocation
- Verify PII is not included in analytics, error tracking, or client-side logging
- Check that PII is not in URLs (appears in server logs, browser history, referrer headers)
- Verify data deletion/anonymization support for GDPR/CCPA compliance

**Severity**: Major if PII is exposed in logs or analytics. Moderate if PII handling is incomplete.

---

## 5. Secrets Management

### 5.1 Hardcoded Secrets

**What to check**: No API keys, passwords, tokens, or connection strings in source code.

**How to check in code**:
- Search for patterns: `API_KEY = "`, `password = "`, `secret = "`, `token = "`, `mongodb://`, `postgres://`, `mysql://`, `redis://`, `sk_live_`, `AKIA` (AWS access key prefix)
- Check test files: test credentials should be clearly fake (e.g., `test_key_not_real`)
- Check config files: `config.js`, `settings.py`, `application.yml`, `appsettings.json`
- Check CI/CD files: `.github/workflows/*.yml`, `Jenkinsfile`, `.gitlab-ci.yml`

**Severity**: Critical. Always. Even if the key is revoked. A committed secret indicates a process failure.

### 5.2 .env Files in Git

**What to check**: `.env` files are in `.gitignore`. No `.env` files with real credentials in the repository.

**How to check in code**:
- Check `.gitignore` for `.env`, `.env.local`, `.env.production`
- Search git history for `.env` files (they may have been committed and then removed but still in history)
- Verify `.env.example` or `.env.template` exists with placeholder values

**Severity**: Critical if `.env` with real secrets is committed. Major if `.env` is not in `.gitignore`.

### 5.3 Secret Rotation

**What to check**: Secrets have a rotation mechanism. Long-lived credentials are avoided where possible.

**How to check in code**:
- Check if short-lived tokens are used where available (AWS STS, GCP service account impersonation)
- Verify there's no reliance on a single long-lived API key with no rotation plan
- Check if the application gracefully handles secret rotation (picks up new values without restart)

**Severity**: Moderate. Important for operational security but not immediately exploitable.

---

## 6. Dependencies

### 6.1 Known CVEs

**What to check**: No dependencies with known HIGH or CRITICAL CVEs that are exploitable in this context.

**How to check in code**:
- Review lockfile for exact versions
- Cross-reference with known CVE databases
- Focus on direct dependencies first, then transitive
- Check if the vulnerable code path is actually used in this application

**Severity**: Critical for exploitable CRITICAL CVEs. Major for exploitable HIGH CVEs. Moderate for MEDIUM CVEs.

### 6.2 Outdated Packages

**What to check**: Dependencies are reasonably up to date, especially security-critical ones (auth libraries, crypto libraries, web frameworks).

**How to check in code**:
- Compare installed versions against latest available versions
- Prioritize: auth/crypto packages, web framework, ORM/database driver
- Check if major version bumps have been skipped (may indicate stale project)

**Severity**: Major if security-critical packages are multiple major versions behind. Moderate otherwise.

### 6.3 Typosquatting Risk

**What to check**: Package names are correct and not slight misspellings of popular packages.

**How to check in code**:
- Review package names in package.json/requirements.txt for plausibility
- Watch for packages with very similar names to popular ones: `lodsah` vs `lodash`, `requets` vs `requests`
- Check download counts and publication dates of unfamiliar packages (new packages with names similar to popular ones are suspicious)

**Severity**: Critical if a typosquatted package is installed (may contain malware).

### 6.4 Lockfile Integrity

**What to check**: Lockfile exists and is committed. Lockfile matches the dependency manifest.

**How to check in code**:
- Verify lockfile exists: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Pipfile.lock`, `Cargo.lock`, `go.sum`
- Verify lockfile is in the git repository (not in `.gitignore`)
- Verify lockfile is consistent with the manifest (no drift)

**Severity**: Major if no lockfile exists (supply chain risk). Moderate if lockfile is inconsistent.

### 6.5 Unnecessary Dependencies

**What to check**: Dependencies are actually used. No leftover packages from removed features.

**How to check in code**:
- Cross-reference package list against imports in source code
- Identify packages that may be unnecessary (e.g., `left-pad`, `is-odd`, single-function packages that could be inlined)
- Each unnecessary dependency increases attack surface

**Severity**: Minor unless the unnecessary dependency has known vulnerabilities.

---

## 7. API Security

### 7.1 Rate Limiting

**What to check**: Rate limiting is implemented on all public endpoints, with stricter limits on auth endpoints.

**How to check in code**:
- Find rate limiting middleware: `express-rate-limit`, `ratelimit`, `throttle`, `@RateLimit`
- Verify it's applied globally or to all routers
- Check limits are appropriate: auth endpoints (5-10/min), API endpoints (100-1000/min depending on use case)
- Verify rate limit state is stored server-side (Redis, in-memory), not in a client cookie

**Severity**: Major if no rate limiting on auth endpoints. Moderate if no rate limiting on other public endpoints.

### 7.2 Input Validation

**What to check**: All input from users is validated for type, length, format, and range.

**How to check in code**:
- Find validation libraries: `joi`, `zod`, `yup`, `class-validator`, `pydantic`, `marshmallow`
- Verify validation is applied on the server side, not just client side
- Check that validation happens before business logic, not after
- Verify error messages don't reveal validation rules that aid attackers

**Severity**: Major at trust boundaries (API endpoints accepting external data). Moderate for internal interfaces.

### 7.3 Output Filtering

**What to check**: API responses don't include internal fields, sensitive data, or more information than the client needs.

**How to check in code**:
- Check if API responses use explicit serialization (allowlist of fields) or implicit (send entire model)
- Verify password hashes, internal IDs, timestamps, and audit fields are not in API responses
- Check error responses: no stack traces, no internal paths, no SQL queries

**Severity**: Major if passwords/tokens are in responses. Moderate if internal data is exposed.

**Common AI mistakes**: `res.json(user)` sending the entire database record including password hash. `res.json({ error: err.message, stack: err.stack })` in production.

### 7.4 CORS Configuration

**What to check**: CORS is configured with specific origins, not wildcard.

**How to check in code**:
- Find CORS configuration: `cors()`, `Access-Control-Allow-Origin`, `@CrossOrigin`
- Verify origin is not `*` on endpoints that require authentication
- Verify credentials mode is not enabled with wildcard origin
- Check `Access-Control-Allow-Methods` is restricted to necessary methods
- Check `Access-Control-Allow-Headers` doesn't include unnecessary headers

**Severity**: Major if `*` with credentials. Moderate if `*` without credentials on authenticated endpoints.

**Common AI mistakes**: `cors()` with no options (allows all origins). `cors({ origin: '*', credentials: true })` (invalid combination that some implementations handle poorly). Origin set to a regex that matches too broadly.

---

## 8. File Handling

### 8.1 Upload Validation

**What to check**: File uploads validate file type, size, and content. Files are stored outside the web root.

**How to check in code**:
- Find upload handling: `multer`, `formidable`, `FileUpload`, `request.FILES`
- Check file type validation: must check magic bytes (file content), not just extension or MIME type from client
- Check file size limits: must be enforced server-side
- Check storage location: files must not be directly executable from the web server

**Severity**: Critical if uploaded files can be executed (PHP, JSP, etc.). Major if file type validation relies only on extension.

### 8.2 Path Traversal in File Operations

**What to check**: File paths constructed from user input are sanitized against directory traversal.

**How to check in code**:
- Find file operations with user-supplied names: `path.join(uploadDir, filename)`, `os.path.join(base, user_input)`
- Verify: `path.resolve()` + `.startsWith(allowedDir)` pattern
- Check for: `../`, URL-encoded variants, null bytes, Windows backslash variants

**Severity**: Critical if arbitrary file read/write is possible. Major if limited traversal is possible.

### 8.3 Temporary File Cleanup

**What to check**: Temporary files created during processing are cleaned up, even on error.

**How to check in code**:
- Find temp file creation: `tmp`, `tempfile`, `mktemp`, `createWriteStream` to temp directories
- Verify cleanup in finally blocks or using automatic cleanup mechanisms
- Check for disk space leaks on error paths

**Severity**: Moderate. Temp file accumulation can cause disk space exhaustion and may contain sensitive data.

---

## 9. Error Handling

### 9.1 Stack Traces in Production

**What to check**: Production error responses do not include stack traces, file paths, or internal details.

**How to check in code**:
- Check for global error handler that sanitizes errors in production
- Search for: `err.stack`, `traceback`, `exception.getMessage()` in response objects
- Verify `NODE_ENV` / `DEBUG` / `FLASK_DEBUG` checks in error handlers
- Check framework default error pages: Express default, Django DEBUG=True, etc.

**Severity**: Moderate. Stack traces reveal internal architecture, file paths, framework versions, and library versions.

### 9.2 User Enumeration via Error Messages

**What to check**: Login, registration, and password reset endpoints return the same error message for valid and invalid users.

**How to check in code**:
- Login: "Invalid credentials" (not "User not found" vs "Wrong password")
- Registration: same response time for existing and new users (or always say "check your email")
- Password reset: "If an account exists, we sent an email" (not "User not found")
- Check timing differences: queries for existing users may take longer than for non-existing ones

**Severity**: Moderate. User enumeration is a reconnaissance step for credential stuffing.

---

## 10. Headers and Configuration

### 10.1 Security Headers

**What to check**: Response includes standard security headers.

**How to check in code**:
- Find header middleware: `helmet`, `SecurityMiddleware`, custom header middleware
- Required headers:
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains` (HSTS)
  - `Content-Security-Policy` (restrict script/style/image sources)
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY` or `SAMEORIGIN`
  - `Referrer-Policy: strict-origin-when-cross-origin` or stricter
  - `Permissions-Policy` (restrict browser features)
  - `X-XSS-Protection: 0` (deprecated but set to 0 to avoid XSS auditor issues)

**Severity**: Moderate for missing individual headers. Major if no security headers at all.

**Common AI mistakes**: Using `helmet()` with all defaults without verifying CSP is configured. Missing HSTS entirely. Setting CSP to `default-src *` (defeats the purpose).

### 10.2 Cookie Flags

**What to check**: Session and authentication cookies have proper security flags.

**How to check in code**:
- Find cookie setting: `res.cookie()`, `Set-Cookie`, `SESSION_COOKIE_*` settings
- Required flags:
  - `HttpOnly` (prevents JavaScript access)
  - `Secure` (HTTPS only)
  - `SameSite=Strict` or `SameSite=Lax` (CSRF protection)
  - `Path=/` (or restricted path)
  - Appropriate `Max-Age` / `Expires`

**Severity**: Major if auth cookie lacks HttpOnly (XSS can steal sessions). Moderate for other missing flags.

---

## 11. AI/LLM Security

*For applications that integrate AI/LLM functionality.*

### 11.1 Prompt Injection (Direct)

**What to check**: User input concatenated into LLM prompts cannot override system instructions.

**How to check in code**:
- Find prompt construction: string concatenation or template literals building prompts
- Check if user input is placed in a clearly delimited section (XML tags, markdown sections)
- Verify system prompt uses firm boundary language
- Check if the application acts on LLM output without validation (tool calls, code execution, data modification)

**Severity**: Critical if LLM output triggers actions (API calls, data writes, code execution). Major if LLM output is displayed to other users (stored prompt injection).

### 11.2 Prompt Injection (Indirect)

**What to check**: External data fed into LLM context (emails, web pages, documents) cannot contain instructions that the LLM follows.

**How to check in code**:
- Find RAG/retrieval pipelines that inject external content into prompts
- Check if retrieved documents are marked as untrusted in the prompt
- Verify LLM output is validated before acting on it

**Severity**: Major. Indirect prompt injection is harder to detect and can exfiltrate data.

### 11.3 Insecure Output Handling

**What to check**: LLM output is treated as untrusted. It must not be rendered as HTML, executed as code, or used in SQL queries without sanitization.

**How to check in code**:
- Find where LLM responses are displayed: `innerHTML`, `dangerouslySetInnerHTML`, `eval()`
- Find where LLM responses are used programmatically: database queries, API calls, file operations
- Verify LLM output is sanitized before rendering and validated before acting on

**Severity**: Critical if LLM output is executed as code. Major if rendered as unsanitized HTML. Major if used in database queries.

### 11.4 Sensitive Information Disclosure

**What to check**: System prompts, internal context, and sensitive data are not extractable through prompt manipulation.

**How to check in code**:
- Check if system prompts contain API keys, internal URLs, or business logic that should be confidential
- Verify the application doesn't return raw LLM responses that include system prompt content
- Check if conversation history management leaks other users' data

**Severity**: Major if system prompts contain secrets. Moderate if internal logic is exposed.

---

## 12. Supply Chain

### 12.1 Dependency Provenance

**What to check**: Dependencies come from expected registries. No internal/private packages referencing public registries.

**How to check in code**:
- Check `.npmrc`, `pip.conf`, `nuget.config` for registry configuration
- Verify scoped packages point to correct registries
- Check for dependency confusion risk: internal package names that could be registered on public registries

**Severity**: Critical if dependency confusion is exploitable. Moderate otherwise.

### 12.2 Build Reproducibility

**What to check**: Builds produce the same output from the same input. No reliance on external state during build.

**How to check in code**:
- Check for `latest` tags in Dockerfiles (`FROM node:latest` should be `FROM node:20.11.0-alpine`)
- Check for unpinned dependencies: `*`, `^`, `~` in production dependency versions
- Verify lockfile is used during CI builds (`npm ci`, not `npm install`)

**Severity**: Moderate. Non-reproducible builds make it impossible to verify what's in production.

### 12.3 CI/CD Pipeline Security

**What to check**: CI/CD pipeline doesn't expose secrets, uses pinned actions, and has appropriate permissions.

**How to check in code**:
- GitHub Actions: pin actions to SHA, not tags (`actions/checkout@abcdef123`, not `actions/checkout@v4`)
- Verify `GITHUB_TOKEN` permissions are minimal
- Check that secrets are not printed to logs (`echo $SECRET`)
- Verify pull request workflows from forks don't have access to secrets

**Severity**: Major if secrets are exposed in CI logs. Moderate for unpinned actions.

### 12.4 Third-Party Script Integrity

**What to check**: Third-party scripts loaded in the browser use Subresource Integrity (SRI) hashes.

**How to check in code**:
- Find `<script src="https://...">` and `<link href="https://...">` tags
- Verify `integrity` attribute is present with a valid hash
- Verify `crossorigin="anonymous"` is set alongside SRI

**Severity**: Moderate. Without SRI, a compromised CDN can inject malicious code.
