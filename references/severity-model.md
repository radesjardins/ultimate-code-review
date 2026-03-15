# UCR Severity Model

This document defines the severity classification system used by all UCR review agents. Every finding must be assigned exactly one severity level and one confidence level. No exceptions.

---

## Severity Levels

### Critical

**Definition**: A defect that is likely exploitable, causes data loss, bypasses authentication or authorization, breaks primary functionality completely, or poses severe trust/reputation risk. Blocks release at ALL strictness levels.

**Criteria** (any one is sufficient):

| Category | Specific Condition |
|---|---|
| Auth bypass | Any path that allows unauthenticated access to authenticated resources |
| Privilege escalation | Any path that allows a lower-privilege user to perform higher-privilege actions |
| SQL injection | Unsanitized user input concatenated into SQL queries |
| Remote Code Execution | User input passed to eval(), exec(), child_process.exec(), os.system(), or equivalent without sanitization |
| SSRF | User-controlled URLs fetched server-side without allowlist validation, especially if internal network is reachable |
| Committed secrets | API keys, passwords, private keys, tokens, connection strings in source files, config files, or test fixtures |
| Data loss | Code path that deletes, overwrites, or corrupts user data under normal (non-error) operation |
| Data corruption | Race condition or logic error that produces invalid data written to persistent storage |
| Functional breakage | Primary user flow completely non-functional (app crashes on launch, main feature throws unhandled exception) |
| Open redirect with data | Unvalidated redirect that carries session tokens, auth codes, or PII to attacker-controlled URL |
| Missing encryption | Sensitive data (passwords, PII, financial data) stored in plaintext or transmitted over unencrypted channel |
| Deserialization | Untrusted data deserialized with pickle, yaml.load(), Java ObjectInputStream, or equivalent |

**Evidence threshold**: Must point to specific file, line number, and code path. Must demonstrate the vulnerability is reachable from user input or normal operation. Theoretical vulnerabilities behind multiple unlikely conditions are not Critical.

**Blocks release**: Always. At every strictness level (mvp, production, public).

---

### Major

**Definition**: A serious defect that creates high operational risk, enables significant security exploitation, causes major UX failure, or is likely to cause a production incident. Blocks release at production and public strictness levels.

**Criteria** (any one is sufficient):

| Category | Specific Condition |
|---|---|
| XSS | Stored or reflected cross-site scripting where user input reaches innerHTML, dangerouslySetInnerHTML, document.write, or equivalent without sanitization |
| CSRF | Missing CSRF token on state-changing operations (POST, PUT, DELETE) that modify user data or settings |
| Broken authorization | Users can access, modify, or delete other users' resources by manipulating IDs, paths, or parameters (IDOR) |
| Missing rate limiting | Authentication endpoints (login, password reset, MFA verification) have no rate limiting or lockout |
| Race condition | Concurrent requests can cause data inconsistency (double-spend, double-submit, check-then-act on shared state) |
| Missing input validation | Data crossing a trust boundary (user input, API response, file upload) is used without type checking, length limits, or format validation |
| Major UX failure | Primary flow broken on a major platform (mobile viewport, common browser), or form that is completely inaccessible |
| Silent data loss | Error handling path that discards user data without notification (catch block that swallows form submission errors) |
| Vulnerable dependency | Direct dependency with a known HIGH or CRITICAL CVE that is exploitable in the context of this application |
| Tenant isolation failure | In multi-tenant apps: any path where tenant A can see or modify tenant B's data |
| Missing TLS | HTTP used where HTTPS is required (API calls with credentials, webhook endpoints) |

**Evidence threshold**: Must identify the specific code pattern and explain the attack vector or failure mode. May reference documentation for CVEs. Should demonstrate the condition is reachable, not merely theoretical.

**Blocks release**: At production and public strictness levels. At mvp, flagged as strong recommendation.

---

### Moderate

**Definition**: A meaningful issue that reduces confidence in the code's correctness, security, or usability. Should be fixed before high-confidence release. Not a hard blocker at mvp.

**Criteria** (any one is sufficient):

| Category | Specific Condition |
|---|---|
| Weak password policy | No minimum length, no complexity requirements, allows common passwords |
| CSRF on non-critical ops | Missing CSRF on operations that don't modify sensitive data (preference changes, non-destructive actions) |
| Performance | Page load >3s, unnecessary re-renders on every keystroke, N+1 queries, missing database indexes on queried columns |
| Missing critical-path tests | No tests for business logic that handles money, permissions, data transformation, or state transitions |
| Inconsistent error handling | Some code paths return error objects, others throw, others return null -- within the same module or feature |
| Accessibility violation | Missing form labels, color contrast below 4.5:1 for body text, interactive elements unreachable by keyboard |
| Missing security logging | Authentication events (login, logout, failed attempts), authorization failures, and data access not logged |
| AI slop: fake error handling | try/catch that logs and continues without recovery, making errors invisible in production |
| AI slop: placeholder stubs | Functions with TODO bodies, hardcoded return values in production paths, empty implementations behind interfaces |
| AI slop: hallucinated imports | Import statements for packages that do not exist in the project's dependency tree |
| Weak cryptography | MD5 or SHA1 used for security purposes (password hashing, token generation, integrity verification) |
| Missing timeout | HTTP requests or database queries with no timeout configured |
| Information disclosure | Verbose error messages that reveal stack traces, file paths, database schemas, or internal service names to end users |

**Evidence threshold**: Must identify the specific code location and explain why it matters. For performance issues, should reference measurable impact or industry benchmarks. For AI slop, must show the specific pattern.

**Blocks release**: At public strictness level. Flagged as recommendation at production. Informational at mvp.

---

### Minor

**Definition**: Cleanup, polish, consistency improvement, or low-risk enhancement. Does not affect correctness or security. Improves maintainability and developer experience.

**Criteria**:

| Category | Specific Condition |
|---|---|
| Code style | Inconsistent naming conventions, mixed quote styles, inconsistent indentation within a file |
| Missing documentation | Non-obvious logic without comments, public API without JSDoc/docstring, complex regex without explanation |
| Dead code | Unreachable code, unused imports, unused variables, commented-out code blocks |
| Suboptimal patterns | Working but less idiomatic approaches (forEach where map is clearer, manual iteration where built-in exists) |
| Missing non-critical tests | Test coverage gaps in utility functions, UI components, or non-business-critical paths |
| Minor UI inconsistency | Slightly different spacing, button sizes, or colors that don't affect usability |
| Redundant code | Duplicate utility functions, re-implemented standard library functionality |
| Naming | Variables or functions with unclear names that require reading the implementation to understand |

**Evidence threshold**: Must identify the specific instance. General observations ("code could be cleaner") are not findings.

**Blocks release**: Never. Included for completeness and continuous improvement.

---

## Confidence Levels

Every finding must include a confidence level:

| Level | Definition | Evidence Required |
|---|---|---|
| **Confirmed** | The issue is demonstrably present. The reviewer has read the code, traced the execution path, and verified the condition exists. | Specific file, line number, code snippet. For security issues: demonstrated attack vector. For functional issues: demonstrated failure scenario. |
| **Probable** | The issue is very likely present based on code patterns, but the reviewer cannot fully confirm without runtime testing or additional context. | Specific file and code pattern. Clear explanation of what would need to be true for this to be a false positive. |
| **Possible** | The issue may be present. The code pattern is suspicious but there may be mitigating factors not visible in the reviewed code. | Specific file and code pattern. Clear explanation of what additional information is needed to confirm or deny. |

**Rules**:
- Critical findings MUST be Confirmed or Probable. A Possible/Critical finding must be downgraded to Major or the confidence must be raised with more evidence.
- Probable and Possible findings must state what would confirm or deny them.
- Do not use Possible as a hedge to include low-quality findings. If you are not at least 50% confident, do not include it.

---

## Finding Format Template

Every finding must follow this exact structure:

```
### [SEVERITY]-[NUMBER]: [Short Title]

**Severity**: Critical | Major | Moderate | Minor
**Confidence**: Confirmed | Probable | Possible
**Category**: [security | functional | performance | ux | accessibility | code-quality | ai-slop]
**File**: `path/to/file.ext` line(s) X-Y
**Blocks Release**: Yes (at [levels]) | No

**Description**:
[One to three sentences describing what the issue is and where it occurs.]

**Evidence**:
```[language]
// The specific code that demonstrates the issue
```

**Impact**:
[What happens if this is not fixed. Be specific: who is affected, what is the failure mode, what is the blast radius.]

**Recommendation**:
```[language]
// Concrete code showing the fix or fix direction
```

**References**: [Optional: CVE numbers, OWASP links, framework docs]
```

Required fields: ALL of them. Optional fields: References only.

---

## Severity Calibration Rules

During the adversarial review phase, severity may be adjusted. The following rules govern adjustments:

### Upgrade Conditions

Upgrade severity when:
- A Moderate finding is on a critical code path (auth, payment, data mutation) -- upgrade to Major
- Multiple Moderate findings in the same area compound to create a systemic risk -- create a new Major finding referencing all of them
- A finding that appears Minor is in code that runs in a security context (middleware, auth handler, input sanitizer) -- upgrade to Moderate minimum
- A race condition initially flagged as Moderate has a financial or data-integrity impact -- upgrade to Major or Critical

### Downgrade Conditions

Downgrade severity when:
- A finding is behind a feature flag that is currently disabled -- downgrade by one level
- A finding is in test code only (not test utilities used by production) -- downgrade to Minor or remove
- A finding requires an already-authenticated attacker with admin privileges -- downgrade by one level
- A finding requires physical access to the server -- downgrade by one level
- The finding is mitigated by infrastructure not visible in code (WAF, reverse proxy, network policy) and this mitigation is documented -- downgrade by one level, note the mitigation

### Never Downgrade When

- The code is in a path reachable by unauthenticated users
- The finding involves PII, financial data, or authentication credentials
- The finding is a committed secret (always Critical, regardless of context)
- The finding involves a known exploited CVE

---

## Release Blocking Criteria by Strictness Level

### mvp

Blocks release:
- Any Critical finding
- No Major or below blocks release

Report includes all severities but only Critical is blocking.

### production

Blocks release:
- Any Critical finding
- Any Major finding with Confirmed confidence
- 3+ Major findings with Probable confidence (systemic quality concern)

### public

Blocks release:
- Any Critical finding
- Any Major finding
- Any Moderate finding in the security or accessibility category
- 5+ Moderate findings of any category (systemic quality concern)
- Missing LICENSE file
- Committed secrets of any kind (even revoked ones -- they indicate process failure)
