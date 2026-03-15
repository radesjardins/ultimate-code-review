# Adversarial Review Protocol

This document defines the structured adversarial review process for UCR Phase 4. The adversarial pass is not "look again" -- it is a systematic challenge of the primary review's findings, a hunt for false negatives, and a calibration of severity ratings.

The adversarial reviewer's job is to make the review ACCURATE, not to make it longer. Remove false positives. Find real false negatives. Correct miscalibrated severity. The output should be a high-confidence, trustworthy report.

---

## Step 1: Challenge High-Severity Findings

For EACH finding rated Critical or Major from the primary review, execute this sequence:

### 1.1 Re-Read the Actual Code

Do not rely on the primary reviewer's code snippet. Read the original file at the referenced line numbers. Verify:
- Does the code actually exist as described?
- Is the line number correct?
- Has surrounding context been omitted that changes the meaning?

### 1.2 Seek Disconfirming Evidence

For each finding, ask: **"What evidence would prove this finding WRONG?"** Then actively look for that evidence.

Specific disconfirming evidence to search for:

| Finding Type | Disconfirming Evidence to Seek |
|---|---|
| SQL injection | Parameterized query wrapper around the raw query; ORM sanitization layer; input validation before the query |
| XSS | Output encoding middleware; CSP header that blocks inline scripts; sanitization library applied before rendering |
| Missing auth | Auth middleware applied at router level (not visible in the handler); reverse proxy auth in front of the app |
| Missing rate limiting | Rate limiting at infrastructure level (API gateway, WAF, nginx config) documented in IaC or config |
| Missing input validation | Validation in middleware, schema validation at framework level, or TypeScript types enforcing constraints |
| Hardcoded secret | Value is a well-known test/example value (e.g., `sk_test_`, placeholder strings); file is in `.gitignore` |
| Missing error handling | Global error handler catches and processes the error; framework provides default error handling |
| Race condition | Database-level constraints (unique index, serializable isolation) that prevent the condition; mutex/lock in shared code |
| Missing CSRF | SameSite cookie attribute set to Strict/Lax; API uses token-based auth (not cookies) making CSRF irrelevant |
| Missing encryption | Encryption handled at infrastructure level (AWS RDS encryption, disk-level encryption) documented in IaC |

### 1.3 Classify the Result

After seeking disconfirming evidence:

- **CONFIRMED**: No disconfirming evidence found. The finding stands as written. The code demonstrably has this issue.
- **CHALLENGED**: Disconfirming evidence exists. Document it. Propose action: remove the finding, downgrade severity, or change confidence to Possible.
- **MODIFIED**: The finding is real but the description, severity, or impact is inaccurate. Provide corrected version.

### 1.4 Verify Severity

For each confirmed finding, apply these reality checks:

1. **Production incident test**: Would this finding cause a production incident that wakes someone up at 3 AM?
   - Yes -> Critical or Major
   - No -> Probably not Critical

2. **Exploitability test**: Could an attacker exploit this remotely, without special access?
   - Yes, unauthenticated attacker -> Critical
   - Yes, authenticated attacker -> Major
   - Yes, but requires admin access -> Moderate
   - Theoretical only -> Moderate or lower

3. **User encounter test**: Would a normal user encounter this in typical usage?
   - Yes, in primary flow -> At least Major
   - Yes, in secondary flow -> At least Moderate
   - Only in edge cases -> Moderate or Minor

4. **Evidence quality test**: Is the evidence confirmed in code, or is it speculation?
   - Confirmed with specific code path -> Keep severity
   - Probable based on patterns -> Do not exceed Major
   - Possible/speculative -> Do not exceed Moderate

---

## Step 2: Investigate Zero-Finding Categories

For EACH review category that produced ZERO findings from the primary review, execute this sequence:

### 2.1 Identify Expected Bug Types

Based on the project type and technology stack, list the 3-5 most common bug types for the zero-finding category.

| Category | Project Type | Most Common Bug Types |
|---|---|---|
| Security | Web app (Node.js) | XSS via template rendering, missing auth on API routes, JWT misconfiguration, IDOR, missing rate limiting |
| Security | Web app (Python) | SQL injection via ORM raw queries, CSRF misconfiguration, secret in settings.py, SSRF, insecure deserialization |
| Security | API (Go) | Missing auth middleware, SQL injection in query builder, insecure TLS config, path traversal in file serving |
| Performance | React SPA | Unnecessary re-renders, missing memo/useMemo, large bundle size, missing code splitting, N+1 API calls |
| Performance | Server-side app | N+1 database queries, missing indexes, no pagination, blocking I/O, no caching |
| Accessibility | Any web app | Missing alt text, missing form labels, keyboard-inaccessible custom components, missing focus management, low contrast |
| Code quality | AI-generated | Fake error handling, placeholder stubs, hallucinated imports, copy-paste structures, inconsistent patterns |
| UX | Any web app | Missing loading states, missing error states, broken mobile layout, missing empty states |

### 2.2 Identify Target Files

For the listed bug types, identify 3-5 files MOST LIKELY to contain them:

- **Security bugs**: Authentication handlers, authorization middleware, API route handlers that accept user input, database query files, file upload handlers
- **Performance bugs**: List/table components, dashboard pages, search functionality, data fetching hooks/services, database query builders
- **Accessibility bugs**: Form components, modal/dialog components, navigation components, custom interactive components, image-heavy pages
- **Code quality bugs**: Utility files, service layers, configuration files, any file with high line count
- **UX bugs**: Form components, error boundary components, loading state components, empty state handling

### 2.3 Targeted Read

Read each identified file specifically looking for the listed bug types. This is not a general review -- it is a targeted search for specific patterns.

For each file:
1. State what you're looking for
2. Read the file
3. Report findings or explicitly state: "Checked [file] for [bug types]. None found. Confidence: [high/medium/low]."

### 2.4 Report Results

If new findings are discovered: add them as new findings in full finding format (same template as primary review).

If no findings are discovered: state the confidence level and what was checked.

```
### Zero-Finding Category: [Category Name]
**Expected bug types checked**: [list]
**Files examined**: [list with line counts]
**Result**: No issues found
**Confidence**: High | Medium | Low
**Confidence reasoning**: [Why this confidence level. "High" means the reviewer is 90%+ confident there are no issues. "Medium" means 70-90%. "Low" means significant areas could not be checked.]
```

---

## Step 3: Review Trust Boundaries

For EACH trust boundary identified during the primary review, execute this adversarial analysis:

### 3.1 Hostile Input Testing

For each trust boundary, ask what happens when the external side sends each of these inputs:

| Input Type | What to Check | Common Failure Mode |
|---|---|---|
| `null` / `undefined` / `None` | Does the code handle null at this boundary? | TypeError/NullPointerException crashes the request |
| Empty string `""` | Is empty string treated as missing or as a valid value? | Empty string passes truthy checks but causes downstream failures |
| Extremely long string (10MB+) | Is there a length limit? | Memory exhaustion, slow regex, database column overflow |
| Wrong type (string where number expected) | Is type coerced or validated? | NaN propagation, string concatenation instead of addition |
| Malicious payload (script tags, SQL, shell commands) | Is input sanitized for the context where it's used? | Injection attacks |
| Valid-looking but semantically wrong data | Does the code validate business rules, not just format? | Data corruption with plausible-looking invalid data |
| Deeply nested object / array | Is nesting depth limited? | Stack overflow, exponential processing time |
| Unicode edge cases (zero-width chars, RTL override, emoji) | Does the code handle unicode correctly? | Display corruption, length validation bypass, homoglyph attacks |

### 3.2 Unavailability Testing

For each external dependency at a trust boundary:

| Condition | What to Check |
|---|---|
| Timeout (no response) | Is there a timeout configured? What happens when it fires? |
| Connection refused | Is the connection error caught? What state is the application in after? |
| Slow response (30+ seconds) | Does the application hang? Are resources (connections, threads) leaked? |
| Partial response (TCP connection drops mid-stream) | Is the partial data handled? Can it corrupt state? |
| Rate limited (429) | Does the application back off? Or does it retry immediately in a tight loop? |

### 3.3 Compromised External Testing

Assume the external side is actively malicious:

| Condition | What to Check |
|---|---|
| Returns crafted malicious data | If the API returns script tags in a field that's rendered to HTML, what happens? |
| Returns valid-format but wrong data | If the API returns another user's data, does the application detect it? |
| Returns different schema than expected | If new fields appear or expected fields are missing, what happens? |
| Returns extremely large response | Is response size limited? Can the external side exhaust application memory? |
| Replays old responses | Is there freshness validation? Could stale data cause incorrect behavior? |

### 3.4 Assumption Documentation

For each trust boundary, identify assumptions the code makes about the external side. Flag any assumption that is:
- Not documented in code comments
- Not validated with runtime checks
- Not protected by a contract (API schema, TypeScript types, database constraints)

---

## Step 4: Review Cross-Component Interactions

For each interaction between components identified during the primary review:

### 4.1 Data Format Agreement

Check: do both sides agree on the data being exchanged?

| Check | How to Verify |
|---|---|
| Field names match | Compare the sending code's field names with the receiving code's expected names. Case sensitivity matters. |
| Field types match | Compare types. Does the sender send a string where the receiver expects a number? ISO date vs Unix timestamp? |
| Required vs optional | If the sender omits a field, does the receiver handle its absence? |
| Null semantics | Does null mean "not set", "explicitly cleared", or is it not expected at all? |
| Array vs single value | Can the field be an array in some cases and a single value in others? |
| Encoding | JSON vs URL-encoded vs multipart? UTF-8 vs Latin-1? |

### 4.2 Error Handling Agreement

Check: do both sides agree on what happens when things go wrong?

| Check | How to Verify |
|---|---|
| Error format | Does the error response format match what the receiver parses? |
| Status codes | Does the receiver handle all status codes the sender can produce? |
| Retry semantics | Is the operation idempotent? If the receiver retries, will the sender handle it correctly? |
| Partial failure | If a batch operation partially succeeds, does the receiver know which items succeeded? |

### 4.3 Timing Assumptions

Check: are there ordering or timing dependencies?

| Check | How to Verify |
|---|---|
| Ordering | Does component A assume component B has already run? Is this guaranteed? |
| Race conditions | Can two requests modify the same data simultaneously? Is there a lock or constraint? |
| Stale reads | If component A reads data, then component B modifies it, then A acts on the stale read, what happens? |
| Timeout cascading | If component A times out waiting for B, does it clean up? Does B know A gave up? |

### 4.4 The CrowdStrike Pattern

Specifically check: when one component produces structured data and another consumes it, do the field counts match? This is the pattern that caused the CrowdStrike global outage -- a template expected N fields but received N-1 or N+1, causing an out-of-bounds read.

- Count the fields in the producer's output
- Count the fields the consumer expects
- If the counts are determined at runtime (dynamic schemas, variable-length arrays): check that the consumer validates the count before accessing by index
- Check for off-by-one in array/list indexing between producer and consumer

---

## Step 5: Severity Calibration

After Steps 1-4, calibrate all findings (original + new) against these criteria:

### Calibration Questions

For EVERY finding at Moderate or above, answer these questions:

1. **Would this finding cause a production incident?**
   - If no -> probably not Critical. Consider Major or lower.
   - If yes -> document the incident scenario.

2. **Would this finding be exploitable by an external attacker?**
   - If yes, without authentication -> at least Major, likely Critical
   - If yes, with authentication -> at least Major
   - If no -> probably not a security Critical

3. **Would a user encounter this in normal use?**
   - If yes, regularly -> at least Moderate
   - If yes, occasionally -> Moderate
   - If only in edge cases -> Minor or Moderate

4. **Is the evidence confirmed in code, or is it speculation?**
   - Confirmed (specific code path traced) -> severity stands
   - Probable (pattern-based, likely but not traced end-to-end) -> do not exceed Major
   - Possible (could be mitigated by factors not visible in code) -> do not exceed Moderate

5. **Would a senior engineer at a reputable company agree with this finding and severity?**
   - If a reasonable senior engineer would say "that's not really an issue" -> consider removal or downgrade
   - If they would say "that's a bug but not that severe" -> downgrade
   - If they would say "that needs to be fixed before release" -> keep or upgrade

### Calibration Rules

- No more than 3 Critical findings per review (if you have more, some are probably Major). Exception: if the codebase genuinely has 4+ Critical issues (committed secrets + SQL injection + auth bypass + data loss), keep all of them, but document why each individually qualifies.
- Moderate findings should outnumber Critical + Major findings in a typical review. If Critical + Major dominate, either the codebase is genuinely dangerous or severity is miscalibrated.
- Minor findings should be present but not dominant. If 80% of findings are Minor, the review may have missed higher-severity issues.
- A finding with Possible confidence should never be Critical. Downgrade to Major or raise the confidence.

---

## Step 6: False Negative Hunting

The final step specifically hunts for issues the primary review missed entirely.

### 6.1 Common Production Incidents

For the project type and stack, identify the 3 most common causes of production incidents:

| Project Type | Top 3 Production Incident Causes |
|---|---|
| Web app (any) | 1. Unhandled error crashes the process 2. Database connection exhaustion 3. Memory leak on long-running processes |
| API service | 1. Missing input validation causes 500 errors 2. Timeout cascade when downstream service is slow 3. Auth bypass on a new endpoint |
| SPA + API | 1. API returns unexpected shape, frontend crashes 2. Race condition between concurrent requests 3. Stale cache serves wrong data |
| E-commerce | 1. Payment processing error not handled 2. Inventory race condition (overselling) 3. PII leak in logs or error messages |
| Mobile app | 1. Offline mode data loss 2. Version incompatibility with API 3. Crash on unexpected server response |

For each: did the primary review check for this? If not, do a targeted check now.

### 6.2 Common Security Vulnerabilities by Stack

| Stack | Top 3 Security Vulnerabilities |
|---|---|
| Node.js + Express | 1. Prototype pollution 2. Path traversal in static file serving 3. ReDoS in user-input regex |
| Python + Django/Flask | 1. SSTI (server-side template injection) 2. SQL injection in raw queries 3. Insecure deserialization |
| React + Next.js | 1. XSS via dangerouslySetInnerHTML 2. SSRF in API routes that fetch URLs 3. Exposed API keys in client bundle |
| Go | 1. Path traversal in http.FileServer 2. TOCTOU in file operations 3. Integer overflow in untrusted input |
| Ruby + Rails | 1. Mass assignment 2. SQL injection in Active Record where 3. Unsafe redirect |
| Java + Spring | 1. SpEL injection 2. XXE in XML parsing 3. Insecure deserialization |

For each: did the primary review check for this? If not, do a targeted check now.

### 6.3 "Too Good to Be True" Analysis

Identify areas of the codebase that look suspiciously perfect -- code that handles something complex with no apparent edge cases, no error handling, and no comments explaining the complexity. These are prime candidates for:
- AI slop (looks complete but isn't)
- Copy-pasted code that worked in a different context
- Code that was simplified during refactoring and lost necessary complexity

For each such area:
1. Identify what makes it suspicious (complex task, simple code, no edge case handling)
2. List 3 edge cases that should be handled
3. Verify whether they are handled (possibly elsewhere in the code)
4. If not handled: add as new finding

---

## Output Structure

The adversarial review MUST produce output in this exact structure:

```markdown
## ADVERSARIAL REVIEW COMPLETE

### Summary
- Primary findings reviewed: [N]
- Confirmed: [N]
- Challenged: [N]
- New findings added: [N]
- Severity adjustments: [N]
- False negative hunts completed: [N categories]

### Confirmed Findings
[List of finding IDs from primary review that are verified correct]
- [ID]: Confirmed. [One sentence on why.]
- [ID]: Confirmed. [One sentence on why.]

### Challenged Findings
[Findings from primary review that the adversarial pass disputes]
- [ID]: CHALLENGED. [Reasoning: what disconfirming evidence was found.]
  Proposed action: [Remove | Downgrade to [severity] | Change confidence to [level]]

### New Findings
[Issues discovered by the adversarial pass that the primary review missed]
[Full finding format for each, using the standard finding template from severity-model.md]

### Severity Adjustments
[Findings where severity was changed]
- [ID]: [Old severity] -> [New severity]. [Reasoning.]

### Disagreements
[Substantive disagreements with the primary review that don't fit the above categories.
These are professional disagreements where reasonable reviewers might differ.
Each must be clearly argued with evidence.]

### Confidence Assessment
Overall review confidence: [High | Medium | Low]
Reasoning: [What was checked, what was NOT checked, what would increase confidence]
Blind spots: [Specific areas that could not be adequately reviewed from static analysis alone]
```

---

## Rules

1. The adversarial pass is not adversarial toward the codebase -- it is adversarial toward the PRIMARY REVIEW. Its job is to make the review accurate.
2. Do not add findings just to have something to add. If the primary review was thorough and accurate, the adversarial pass may have mostly Confirmed findings and zero New Findings. That's fine.
3. Do not remove findings just to reduce the count. If the primary review found real issues, confirm them.
4. Every challenge must have evidence. "I don't think this is a real issue" is not a challenge. "This is mitigated by the global error handler at app.js:45 which catches and logs all unhandled errors" is a challenge.
5. Every new finding must meet the same evidence standards as primary findings. No speculative additions.
6. The adversarial pass should take approximately 30-40% of the time the primary review took. It is a focused, targeted effort, not a second full review.
