# API Review Module

> Loaded when project matches: REST, GraphQL, gRPC, WebSocket APIs (Express, Fastify, Flask, FastAPI, Django, Go net/http, Rust Actix/Axum)

## Detection Heuristics

Activate this module when any of the following are found:
- `package.json` contains `express`, `fastify`, `@nestjs/core`, `hono`, `koa`
- `requirements.txt` or `pyproject.toml` contains `flask`, `fastapi`, `django`, `djangorestframework`
- `go.mod` with `net/http` usage, `gin-gonic`, `echo`, `fiber`, `chi`
- `Cargo.toml` with `actix-web`, `axum`, `rocket`, `warp`
- Presence of `schema.graphql`, `.gql` files, or `graphql` dependency
- Protobuf files (`.proto`) indicating gRPC
- Route/endpoint definition files, controller directories, handler directories

---

## Endpoint Security

| Check | Severity | Description |
|-------|----------|-------------|
| Endpoint missing auth middleware | CRITICAL | Any endpoint handling user data or mutations lacks authentication check |
| No rate limiting on auth endpoints | CRITICAL | Login, register, password reset have no rate limiting; enables brute force |
| No rate limiting on API endpoints | HIGH | Public or authenticated endpoints have no request throttling |
| Input not validated before use | CRITICAL | Request body/params/query used directly without schema validation |
| Response includes internal fields | HIGH | Database IDs, internal flags, or user fields (password hash, email) leaked in response |
| Missing authorization check | CRITICAL | Auth confirms identity but endpoint doesn't check if user can access THIS resource (IDOR) |

### Detection patterns:
- Route definitions without auth middleware in the chain: `app.get('/api/users/:id', handler)` (no auth before handler)
- Controller methods that access `req.params.id` and query database without checking ownership
- Express: missing `helmet()`, missing rate-limit middleware
- FastAPI: endpoints without `Depends(get_current_user)`
- Django: views without `@login_required` or permission classes

---

## API Design

| Check | Severity | Description |
|-------|----------|-------------|
| Inconsistent response format | MEDIUM | Some endpoints return `{ data: ... }`, others return raw objects, others return `{ result: ... }` |
| Wrong HTTP status codes | MEDIUM | `200` for created resource (should be `201`), `200` for deleted (should be `204`), `500` for validation error (should be `400/422`) |
| Missing pagination | HIGH | List endpoints return all records; no limit/offset or cursor-based pagination |
| No API versioning strategy | MEDIUM | No URL prefix (`/v1/`), no header-based versioning; breaking changes will affect all clients |
| Inconsistent naming | LOW | Mix of `camelCase` and `snake_case` in response fields, or inconsistent pluralization |
| Missing HATEOAS or next links | LOW | Paginated responses missing `next`/`prev` links or cursor tokens |

---

## GraphQL-Specific

| Check | Severity | Description |
|-------|----------|-------------|
| No query depth limit | CRITICAL | Deeply nested queries can cause exponential database load; no `depthLimit` plugin |
| No query complexity analysis | HIGH | No cost analysis; a single query can request all records of all types |
| Introspection enabled in production | HIGH | `__schema` and `__type` queries expose entire API surface to attackers |
| N+1 resolver queries | HIGH | Resolver fetches one record per parent item; missing DataLoader or equivalent batching |
| No persisted queries | MEDIUM | Arbitrary queries accepted; consider persisted/allowlisted queries in production |
| Batching without limits | HIGH | Accepts array of operations with no limit on batch size |

### Detection patterns:
- Missing `depthLimit` or `queryComplexity` in GraphQL server setup
- Resolver functions that call `db.find()` without DataLoader wrapping
- `introspection: true` or no introspection configuration (defaults to enabled)
- No `validationRules` array in server configuration

---

## Request Validation

| Check | Severity | Description |
|-------|----------|-------------|
| No schema validation library | HIGH | Request bodies used without Zod, Joi, Pydantic, marshmallow, or equivalent |
| Partial validation | HIGH | Top-level fields validated but nested objects pass through unvalidated |
| Type coercion attacks | HIGH | String `"0"` coerced to falsy, `"true"` accepted as boolean, array passed where string expected |
| Missing Content-Type check | MEDIUM | Endpoint doesn't verify `Content-Type` header matches expected format |
| File upload without type validation | CRITICAL | File accepted based on extension only; no magic byte / MIME type validation |
| Integer overflow on IDs | MEDIUM | Numeric IDs not range-checked; very large numbers cause issues |

### Detection patterns:
- `req.body.email` used directly without prior validation step
- Zod/Joi schema defined but not applied as middleware
- `JSON.parse()` without try-catch
- Python: `request.json['field']` without Pydantic model or marshmallow schema

---

## Error Responses

| Check | Severity | Description |
|-------|----------|-------------|
| Stack traces in production | CRITICAL | Error responses include stack traces, file paths, or line numbers |
| Database errors forwarded | CRITICAL | Raw database error messages (column names, table names, constraint names) returned to client |
| Different status for auth vs not-found | HIGH | `403` for existing resource vs `404` for non-existing leaks resource existence information |
| Inconsistent error format | MEDIUM | Some errors return `{ error: "msg" }`, others `{ message: "msg" }`, others plain strings |
| Missing error codes | MEDIUM | Errors lack machine-readable code; clients can only parse human-readable message |
| Unhandled promise rejections | CRITICAL | Async errors not caught; Express returns default 500 with no useful info (or crashes) |

### Detection patterns:
- `catch(err) { res.status(500).json(err) }` — forwards entire error object
- `catch(err) { res.status(500).json({ error: err.message }) }` — exposes internal message
- Missing global error handler (Express: no `app.use((err, req, res, next) => ...)`)
- Python: missing exception handler; default Django/Flask 500 page in production

---

## Database Queries

| Check | Severity | Description |
|-------|----------|-------------|
| SQL injection via concatenation | CRITICAL | String concatenation or template literals to build SQL: `` `SELECT * FROM users WHERE id = ${id}` `` |
| ORM misuse enabling injection | HIGH | Raw query methods with user input: `sequelize.query()`, `knex.raw()`, `django.db.connection.cursor()` |
| N+1 queries | HIGH | Loop that executes one query per iteration; missing eager loading / joins |
| Missing database indexes | MEDIUM | Queries filter on columns without indexes; will degrade at scale |
| No query timeouts | MEDIUM | Long-running queries have no statement timeout; can lock resources |
| Transactions missing for multi-step operations | HIGH | Multiple related writes without transaction; partial failure leaves inconsistent state |
| Unbounded SELECT | HIGH | `SELECT *` or `findAll()` without LIMIT; can return millions of rows |

### Detection patterns:
- Template literals or string concatenation with SQL keywords: `"SELECT"`, `"INSERT"`, `"UPDATE"`, `"DELETE"`
- ORM `.query()` or `.raw()` methods with interpolated variables
- Loop containing `await db.find()` or `await Model.findOne()`
- Missing `.limit()` on query builders; missing `LIMIT` in raw SQL

---

## Authentication

| Check | Severity | Description |
|-------|----------|-------------|
| JWT `alg: none` not rejected | CRITICAL | JWT library accepts unsigned tokens; must explicitly require specific algorithm |
| JWT algorithm confusion | CRITICAL | Library accepts both HS256 and RS256; attacker signs with public key using HS256 |
| JWT secret too short | HIGH | HMAC secret is short string; brute-forceable. Must be 256+ bits of entropy |
| Missing JWT expiry validation | HIGH | Token accepted regardless of `exp` claim; or `exp` set to years |
| No refresh token rotation | MEDIUM | Refresh tokens reusable indefinitely; stolen refresh token = permanent access |
| Session fixation possible | HIGH | Session ID not regenerated after login; pre-auth session ID works post-auth |
| API keys in query params | HIGH | API keys passed as URL parameter; logged in server logs, proxy logs, browser history |

### Detection patterns:
- JWT library initialized without specifying `algorithms` option
- `jwt.verify(token, secret)` without `{ algorithms: ['HS256'] }` or equivalent
- Secret loaded from env var but env var is `"secret"` or `"jwt-secret"` in defaults
- Token expiry set >24h for access tokens

---

## CORS

| Check | Severity | Description |
|-------|----------|-------------|
| Wildcard origin with credentials | CRITICAL | `Access-Control-Allow-Origin: *` with `Access-Control-Allow-Credentials: true` |
| Origin reflected from request | CRITICAL | Server copies `Origin` header to `Access-Control-Allow-Origin` without allowlist check |
| Overly permissive origins | HIGH | `*.example.com` allows any subdomain; compromised subdomain = full access |
| Missing CORS on API | MEDIUM | No CORS headers at all; only works same-origin, breaks legitimate clients |
| Preflight cache too long | LOW | `Access-Control-Max-Age` set to days; CORS policy changes won't take effect |

### Detection patterns:
- `cors({ origin: '*', credentials: true })`
- `cors({ origin: true })` — reflects any origin
- `res.setHeader('Access-Control-Allow-Origin', req.headers.origin)`
- CORS middleware configured but only in development

---

## File Handling

| Check | Severity | Description |
|-------|----------|-------------|
| No upload size limit | HIGH | Missing `limits` config on multer/busboy/formidable; unlimited upload can exhaust disk/memory |
| Extension-only type check | HIGH | File type checked by extension, not magic bytes or MIME validation |
| Path traversal in filename | CRITICAL | Uploaded filename used directly in path: `path.join(uploadDir, req.file.originalname)` |
| Uploaded files executable | CRITICAL | Upload directory allows execution; uploaded `.php`, `.jsp`, `.cgi` file runs on server |
| No virus/malware scanning | MEDIUM | Uploaded files served to other users without malware scan |
| Missing file cleanup | MEDIUM | Temporary upload files not cleaned up on processing failure |

---

## Common AI Slop

| Pattern | Severity | What to look for |
|---------|----------|------------------|
| Success regardless of outcome | CRITICAL | `res.json({ success: true })` returned even when the operation failed or was a no-op |
| Missing error handling on DB ops | CRITICAL | `await db.save(record)` without try-catch; unhandled rejection crashes server |
| Auth middleware inconsistently applied | CRITICAL | Some routes in a group have auth, others don't; pattern suggests copy-paste omission |
| Hardcoded CORS origins | HIGH | `origin: 'http://localhost:3000'` in production code; or both localhost and production mixed |
| Catch-all error swallowing | CRITICAL | `catch (e) { return res.status(500).json({ error: 'Something went wrong' }) }` with no logging |
| Fake async operations | MEDIUM | `async` function that contains no `await`; added `async` keyword reflexively |
| Identical CRUD boilerplate | MEDIUM | Every resource has identical create/read/update/delete with no business logic differences |
| Environment checks as strings | HIGH | `if (process.env.NODE_ENV === 'production')` controlling security features; can be bypassed if env var missing |
| Console.log as logging | HIGH | `console.log` used for production logging instead of structured logger (pino, winston, logging module) |
| In-memory storage | CRITICAL | Using `Map()` or global object as data store; data lost on restart, no persistence |

---

## Testing Requirements

| Requirement | Priority | Details |
|-------------|----------|---------|
| Happy path per endpoint | REQUIRED | Each endpoint tested with valid input returning expected response |
| Error cases per endpoint | REQUIRED | Invalid input, missing fields, wrong types return proper error responses |
| Auth bypass tests | REQUIRED | Every protected endpoint tested without auth token; must return 401/403 |
| Input validation tests | REQUIRED | Boundary values, type coercion, injection payloads tested |
| Rate limiting tests | RECOMMENDED | Verify rate limit headers and blocking after threshold |
| Concurrent request tests | RECOMMENDED | Race conditions on create, update, delete operations |
| Integration tests with real DB | REQUIRED | Not just mocked; actual database operations verified |
| Contract tests | RECOMMENDED | OpenAPI/GraphQL schema validated against actual responses |

### Minimum coverage expectations:
- All endpoints: happy path + at least 2 error cases
- Authentication: token expiry, invalid token, missing token, wrong role
- Authorization: own resource vs other user's resource
- Database operations: create, read, update, delete, list with pagination
