# SaaS Application Review Module

> Loaded when project matches: Multi-tenant applications, subscription-based services

## Detection Heuristics

Activate this module when any of the following are found:
- Database models/schemas with `tenant_id`, `organization_id`, `org_id`, `team_id`, `workspace_id` fields
- Dependencies: `stripe`, `@stripe/stripe-js`, `paddle`, `chargebee`, `lemon-squeezy`
- Multi-tenant middleware or scope filtering patterns in ORM layer
- Presence of `plans`, `subscriptions`, `billing`, `tenants`, `organizations` tables/collections
- Auth system with roles: `owner`, `admin`, `member`, `viewer` in code or schema
- Invitation/onboarding flow code: `invitations` table, `invite_token`, `onboarding` routes
- Admin panel routes: `/admin/`, `/dashboard/admin/`, dedicated admin app

---

## Tenant Isolation

| Check | Severity | Description |
|-------|----------|-------------|
| Query missing tenant scope | CRITICAL | Database query fetches records without filtering by tenant; cross-tenant data leak |
| Tenant ID from client trusted | CRITICAL | Tenant ID from request body/params instead of derived from authenticated session |
| Missing tenant middleware | HIGH | No global middleware ensuring every query is tenant-scoped; relies on developers remembering |
| Direct object reference without tenant check | CRITICAL | `GET /api/documents/:id` fetches by ID only; doesn't verify document belongs to requesting tenant |
| Shared resources without isolation | HIGH | File uploads, cache keys, or queue jobs not namespaced by tenant; collision or leakage |
| Admin endpoints bypass tenant scope | HIGH | Admin queries fetch across tenants but don't require admin role verification |

### Detection patterns:
- ORM queries: `Model.findById(id)` without `.where('tenant_id', tenantId)` or equivalent scope
- SQL: `SELECT * FROM documents WHERE id = $1` missing `AND tenant_id = $2`
- Missing global query scope: no default scope, no middleware that injects `tenant_id` filter
- File upload paths: `uploads/${filename}` instead of `uploads/${tenantId}/${filename}`
- Cache keys: `cache:user:${userId}` instead of `cache:${tenantId}:user:${userId}`
- Background job payloads missing `tenantId` field

### Tenant scoping patterns to verify:
```
[ ] Every database query includes tenant_id filter (or uses scoped model/view)
[ ] Tenant ID is NEVER taken from request body; always derived from auth session
[ ] File storage paths are namespaced by tenant
[ ] Cache keys are namespaced by tenant
[ ] Background job payloads include tenant_id and worker validates it
[ ] Search indexes are filtered by tenant
[ ] API responses never include data from other tenants
[ ] Aggregate queries (counts, sums) are scoped to tenant
```

---

## Authentication System

| Check | Severity | Description |
|-------|----------|-------------|
| Password hashing algorithm | CRITICAL | Must use bcrypt, scrypt, or Argon2 with appropriate cost factor; flag MD5, SHA-1, SHA-256 without salt |
| Missing email verification | HIGH | Account created without email verification; enables account creation with others' emails |
| Password reset token reuse | CRITICAL | Reset token not invalidated after use; link works repeatedly |
| Password reset token lifetime | HIGH | Token valid for >1 hour; should be 15-60 minutes |
| No account lockout | HIGH | Unlimited login attempts; brute force enabled |
| Session not invalidated on password change | HIGH | Existing sessions continue working after password change; compromised session persists |
| Missing MFA option | MEDIUM | No TOTP/WebAuthn option for accounts; single factor only |
| Registration rate limiting | HIGH | No limit on account creation; enables spam account creation |

### Detection patterns:
- `crypto.createHash('md5')` or `hashlib.md5` for password hashing
- Password reset: token generated but no expiry field, or expiry >3600 seconds
- Login handler without attempt counting or rate limiting
- `POST /auth/register` without rate limit middleware
- Session table/store not cleared when password changes: missing `DELETE FROM sessions WHERE user_id = $1`

---

## Authorization

| Check | Severity | Description |
|-------|----------|-------------|
| No role-based access control | HIGH | All authenticated users have equal access; no admin/member/viewer distinction |
| Role check only in UI | CRITICAL | UI hides admin buttons but API endpoints don't verify role |
| Missing org-level permission check | HIGH | User in org A can access org B's resources by knowing the ID |
| Invitation flow bypasses verification | HIGH | Invite link grants access without email verification; anyone with link gets access |
| Permission escalation via API | CRITICAL | User can modify their own role by sending `role: "admin"` in profile update request |
| Missing permission inheritance | MEDIUM | Org admin can't access team resources; or team permissions don't flow from org |

### Detection patterns:
- API handlers checking `req.user.isAuthenticated` but not `req.user.role`
- `UPDATE users SET role = $1 WHERE id = $2` without checking caller's permission to assign roles
- Invitation acceptance endpoint that doesn't verify email matches invitation target
- Organization membership endpoints that don't verify requesting user is org admin
- Missing `@RequireRole('admin')` or equivalent decorator on admin API routes

### Authorization model checklist:
```
[ ] Every API endpoint checks both authentication AND authorization
[ ] Role is determined server-side, never accepted from client request
[ ] Organization membership verified on every org-scoped operation
[ ] Team membership verified on every team-scoped operation
[ ] Invitation flow validates email matches recipient
[ ] Role assignment requires admin privilege
[ ] Permission changes take effect immediately (not cached indefinitely)
```

---

## Billing Integration

| Check | Severity | Description |
|-------|----------|-------------|
| Webhook signature not verified | CRITICAL | Stripe/Paddle webhook processed without verifying signature; attacker can fake events |
| Plan enforcement on frontend only | CRITICAL | Feature limits checked in UI but not enforced server-side; API access bypasses limits |
| Missing subscription lifecycle handling | HIGH | No handling for: trial end, payment failure, subscription cancel, plan change |
| PCI data handled directly | CRITICAL | Raw credit card numbers processed by your server; must use tokenization (Stripe Elements, etc.) |
| No idempotency on payment operations | HIGH | Webhook retry or network error causes duplicate charges or duplicate plan activations |
| Trial manipulation | HIGH | User can create multiple accounts for unlimited trials; no credit card requirement or fingerprinting |
| Missing grace period | MEDIUM | Payment failure immediately locks account; should provide retry window |
| Subscription state not synced | HIGH | Local subscription state diverges from payment provider; features enabled for cancelled accounts |

### Detection patterns:
- Webhook handler without `stripe.webhooks.constructEvent(body, sig, secret)` or equivalent verification
- Feature checks: `if (user.plan === 'pro')` in React but no corresponding server-side check on the API endpoint
- Missing webhook handlers for: `customer.subscription.deleted`, `invoice.payment_failed`, `customer.subscription.updated`
- `req.body.cardNumber` appearing anywhere in backend code (PCI violation)
- Webhook handler without idempotency key check; duplicate processing possible

### Billing webhook checklist:
```
[ ] Webhook signature verified using provider's SDK
[ ] Events processed idempotently (check event ID, don't reprocess)
[ ] subscription.created: activate features, record start date
[ ] subscription.updated: handle plan change, proration
[ ] subscription.deleted: revoke features, handle grace period
[ ] invoice.payment_failed: notify user, retry logic, eventual downgrade
[ ] customer.deleted: handle account deletion from provider side
[ ] All webhook events logged for audit trail
```

---

## Rate Limiting

| Check | Severity | Description |
|-------|----------|-------------|
| No rate limiting at all | HIGH | No request throttling; single tenant can consume all resources |
| Rate limit per IP only | MEDIUM | Authenticated requests should be rate-limited per user/tenant, not just IP |
| No per-tenant resource quotas | HIGH | One tenant's heavy usage degrades performance for all tenants |
| Rate limit headers missing | LOW | No `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers; clients can't self-throttle |
| Bypass via API key rotation | MEDIUM | Rate limit per API key; user generates new key to reset limit |
| No abuse detection | MEDIUM | Unusual patterns (scraping, bulk operations) not detected or flagged |

### Detection patterns:
- No rate limit middleware in API route chain
- Rate limiter keyed only on IP: `rateLimit({ keyGenerator: (req) => req.ip })`
- Missing separate limits for different endpoint categories (auth endpoints need stricter limits)
- No monitoring/alerting for rate limit violations

---

## Data Management

| Check | Severity | Description |
|-------|----------|-------------|
| No data export capability | HIGH | Users cannot export their data; GDPR Article 20 (right to data portability) |
| No account deletion flow | CRITICAL | No way to delete account and all associated data; GDPR Article 17 (right to erasure) |
| Missing data retention policy | MEDIUM | No defined policy for how long data is kept; no automatic cleanup of old data |
| No per-tenant backup strategy | MEDIUM | Backup is system-wide only; cannot restore single tenant's data without affecting others |
| Soft delete without purge | MEDIUM | Records soft-deleted but never hard-deleted; PII retained indefinitely |
| Audit log gaps | MEDIUM | Sensitive operations (data access, exports, admin actions) not logged |

### Data deletion checklist (account deletion):
```
[ ] User record deleted or anonymized
[ ] All tenant data deleted (documents, files, settings)
[ ] File storage (S3, etc.) cleaned up
[ ] Cache entries removed
[ ] Search index entries removed
[ ] Background job queue entries removed
[ ] Third-party integrations notified (Stripe customer deleted, etc.)
[ ] Audit log retained (anonymized) for compliance
[ ] Confirmation email sent
[ ] Session/tokens invalidated
```

---

## Onboarding

| Check | Severity | Description |
|-------|----------|-------------|
| Default config is insecure | HIGH | New tenant created with permissive defaults (public sharing, weak password policy) |
| Missing setup validation | MEDIUM | Setup wizard allows skipping critical steps; tenant in partially configured state |
| Sample data not clearly marked | MEDIUM | Demo/sample data created on signup looks like real data; user confusion |
| No idempotent setup | MEDIUM | Re-running setup creates duplicates; setup endpoint must handle re-entry |
| Missing onboarding state tracking | LOW | No way to resume interrupted onboarding; user starts over |

---

## Email and Notifications

| Check | Severity | Description |
|-------|----------|-------------|
| Email spoofing possible | HIGH | Transactional emails lack SPF, DKIM, DMARC configuration |
| Email verification link reuse | HIGH | Verification link works after being used once; should be single-use |
| No unsubscribe mechanism | MEDIUM | Marketing/notification emails lack one-click unsubscribe; CAN-SPAM violation |
| Notification preferences ignored | MEDIUM | No preference system; or preferences stored but emails sent regardless |
| PII in email subject | MEDIUM | Sensitive information in email subject line (visible in inbox preview, email logs) |
| Email content injection | HIGH | User-controlled data in email body without escaping; HTML injection in HTML emails |

### Detection patterns:
- Email sending without checking user's notification preferences
- Verification tokens without single-use flag or expiry
- `sendEmail({ subject: \`Reset for ${user.email}\` })` - email in subject
- HTML email templates with `${user.name}` without HTML escaping

---

## Admin Panel

| Check | Severity | Description |
|-------|----------|-------------|
| Admin auth same as user auth | HIGH | Admin panel uses same session/JWT as user dashboard; no elevated auth for admin |
| No audit logging for admin actions | HIGH | Admin can modify/delete tenant data without record; no accountability |
| Admin can impersonate without logging | CRITICAL | Impersonation feature doesn't log who impersonated whom and when |
| Missing admin RBAC | HIGH | All admins have equal access; no distinction between support and super-admin |
| Admin endpoints in main API | MEDIUM | Admin routes in same router as user routes; easier to accidentally expose |
| Mass operations without confirmation | MEDIUM | Admin can delete all tenants or users without confirmation step |

### Detection patterns:
- Admin routes using same auth middleware as user routes without additional role check
- Impersonation endpoint without audit log write
- Missing `@AdminOnly` or `requireRole('admin')` on admin controllers
- Admin routes defined alongside public routes in same router file

---

## Common AI Slop

| Pattern | Severity | What to look for |
|---------|----------|------------------|
| Tenant ID not validated on queries | CRITICAL | `findById(id)` without tenant scope; AI often forgets multi-tenancy in data access |
| Admin endpoints without auth | CRITICAL | `/admin/users` accessible without admin role check; AI generates route but not auth |
| Webhooks without signature verification | CRITICAL | Billing webhook handler processes request body without verifying Stripe/provider signature |
| No rate limiting anywhere | HIGH | API has no rate limiting middleware; AI generates endpoints but not infrastructure |
| Hardcoded plan limits | HIGH | `if (documents.length >= 100)` instead of reading limit from plan configuration |
| No data export functionality | HIGH | CRUD operations without export endpoint; AI builds features but not data portability |
| Role stored in JWT without server check | HIGH | Role from JWT payload trusted without checking against database; stale after role change |
| Permission checks in middleware but not on query | HIGH | Auth middleware verifies user role but database query still fetches across tenants |
| Billing state cached indefinitely | HIGH | Subscription status cached without TTL; cancelled subscription still shows as active |
| Error messages leak tenant info | MEDIUM | Error says "Organization 'Acme Corp' not found" instead of generic "Not found" |

---

## Compliance Readiness

| Check | Severity | Description |
|-------|----------|-------------|
| No privacy policy | HIGH | SaaS application handling user data without privacy policy |
| No cookie consent | MEDIUM | Cookies set without user consent mechanism (EU requirement) |
| No DPA available | MEDIUM | No Data Processing Agreement template for enterprise customers |
| PII not identified | HIGH | No documentation of what PII is collected, where stored, and how long retained |
| No breach notification plan | MEDIUM | No documented process for notifying users of data breach (72h GDPR requirement) |
| Cross-border data transfers | MEDIUM | Data stored/processed in different jurisdictions without user awareness |

### GDPR basics checklist:
```
[ ] Privacy policy describes what data is collected and why
[ ] Users can access all their data (Article 15)
[ ] Users can correct their data (Article 16)
[ ] Users can delete their data (Article 17)
[ ] Users can export their data (Article 20)
[ ] Cookie consent mechanism for non-essential cookies
[ ] Data processing records maintained
[ ] Data breach notification process documented
[ ] DPA template available for enterprise customers
[ ] Sub-processors listed and documented
```

---

## Testing Requirements

| Requirement | Priority | Details |
|-------------|----------|---------|
| Tenant isolation tests | REQUIRED | User A cannot access User B's data through any endpoint; test with multiple tenants |
| Billing flow tests | REQUIRED | Subscribe, upgrade, downgrade, cancel, payment failure all handled correctly |
| Permission boundary tests | REQUIRED | Each role tested against each endpoint; viewer can't write, member can't admin |
| Concurrent tenant tests | RECOMMENDED | Multiple tenants operating simultaneously; no race conditions on shared resources |
| Data deletion tests | REQUIRED | Account deletion removes all associated data from all storage systems |
| Webhook replay tests | REQUIRED | Same webhook event processed twice produces same result (idempotency) |
| Rate limit tests | RECOMMENDED | Verify limits are enforced per tenant; one tenant's load doesn't affect another |
| Migration tests | RECOMMENDED | Database migrations work on production-sized data; no downtime migration path |

### Multi-tenant test pattern:
```
1. Create Tenant A and Tenant B
2. Create resources in Tenant A
3. Authenticate as Tenant B user
4. Attempt to access Tenant A resources by ID -> must return 404 (not 403)
5. Attempt to list resources -> must return only Tenant B resources
6. Attempt to modify Tenant A resources -> must return 404
7. Verify Tenant A resources are unchanged
```

### Billing test scenarios:
```
[ ] New subscription: features activated, welcome email sent
[ ] Plan upgrade: prorated, features immediately available
[ ] Plan downgrade: effective at period end, features available until then
[ ] Payment failure: notification sent, retry scheduled, grace period active
[ ] Subscription cancelled: features available until period end, then revoked
[ ] Trial expiry: prompt to subscribe, features limited/revoked
[ ] Webhook replay: no duplicate charges, no duplicate emails
[ ] Concurrent plan changes: no race condition, last write wins consistently
```
