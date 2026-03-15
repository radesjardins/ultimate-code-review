# AI Slop Detection Patterns

This document catalogs code anti-patterns commonly produced by AI code generators. These patterns are dangerous because they look correct at a glance -- they have the shape of working code without the substance. Detection of these patterns is a core differentiator of the UCR skill.

Every pattern below includes detection heuristics that a code reviewer can apply mechanically. When reviewing AI-generated or AI-assisted code, apply ALL of these checks.

---

## 1. Hallucinated Imports

**Description**: AI models generate import statements for packages, modules, or functions that do not exist. The model has seen similar package names in training data and invents a plausible-sounding one. Research shows 43% of hallucinated packages recur across queries, making them a vector for dependency confusion attacks.

**Detection heuristic**:
- For every import statement, verify the package exists in the project's lockfile (package-lock.json, yarn.lock, Pipfile.lock, Cargo.lock, go.sum)
- For relative imports, verify the file path resolves to an actual file
- For submodule imports (e.g., `from package.submodule import thing`), verify that `thing` actually exists in that submodule
- Watch for packages with names that are close to real packages but slightly different (e.g., `python-dotenv` vs `dotenv` vs `python-env`)

**Severity**: Moderate if the code won't compile/run (it will fail immediately). Critical if someone could register the hallucinated package name and execute a supply chain attack (especially in npm where package registration is open).

**Example of bad code**:
```python
from flask_security_utils import generate_csrf_token
from utils.auth_helpers import validate_jwt_claims
```
Where `flask_security_utils` does not exist on PyPI, and `utils/auth_helpers.py` does not exist in the project.

**Example of correct code**:
```python
from flask_wtf.csrf import generate_csrf
from jose import jwt  # python-jose package, present in requirements.txt
```

**Why it's dangerous**: The code will fail at import time in the best case. In the worst case, an attacker registers the hallucinated package name on a public registry, populates it with malicious code, and waits for someone to `pip install` or `npm install` the fake dependency. This is not theoretical -- it has happened repeatedly in the npm and PyPI ecosystems.

---

## 2. Fake Error Handling

**Description**: AI generates try/catch blocks that give the appearance of error handling without actually handling anything. The catch block logs the error (or doesn't) and execution continues as if nothing happened. The function returns undefined, null, or a default value, and the caller has no way to know something went wrong.

**Detection heuristic**:
- Find all try/catch blocks. For each catch block, check:
  - Does it ONLY contain console.log/console.error/print/logging.error?
  - Does it return null/undefined/None/empty string/empty array/0?
  - Does it have a comment like `// handle error` or `# TODO: handle error` with no actual handling?
  - Does it re-throw a different (less informative) error?
  - Does it swallow the error entirely (empty catch block)?
- Find all `.catch()` handlers on promises. Same checks apply.
- In Python, find bare `except:` or `except Exception:` blocks that use `pass`.

**Severity**: Major if in a data mutation path (user could lose data without knowing). Moderate in read paths. Critical if in authentication/authorization code (auth errors silently succeed).

**Example of bad code**:
```javascript
async function saveUserProfile(userId, data) {
  try {
    const result = await db.users.update(userId, data);
    return result;
  } catch (error) {
    console.error('Error saving profile:', error);
    return null;
  }
}

// Caller has no idea the save failed:
const result = await saveUserProfile(userId, formData);
showToast('Profile saved!'); // Always shows success
```

**Example of correct code**:
```javascript
async function saveUserProfile(userId, data) {
  try {
    const result = await db.users.update(userId, data);
    return { success: true, data: result };
  } catch (error) {
    logger.error('Failed to save user profile', { userId, error: error.message });
    // Rethrow so the caller can handle the failure in the UI
    throw new AppError('PROFILE_SAVE_FAILED', 'Could not save your profile. Please try again.', { cause: error });
  }
}

// Caller handles the error:
try {
  await saveUserProfile(userId, formData);
  showToast('Profile saved!');
} catch (error) {
  showToast('Failed to save profile. Please try again.', 'error');
}
```

**Why it's dangerous**: Silent failures are the #1 cause of data loss in production. Users believe their data was saved when it wasn't. In financial contexts, transactions appear to succeed when they failed. In auth contexts, authentication may silently fall through to an unauthenticated state.

---

## 3. Placeholder Stubs

**Description**: AI generates function signatures and bodies that look complete but contain TODO comments, hardcoded return values, pass-through logic, or empty implementations. The code compiles and may even pass basic tests but does not implement the required behavior.

**Detection heuristic**:
- Search for `TODO`, `FIXME`, `HACK`, `XXX`, `PLACEHOLDER` in production code paths (not test files)
- Find functions that return hardcoded values (especially `return true`, `return []`, `return {}`, `return "success"`)
- Find functions whose body is only `pass` (Python), `{}` (JS/TS), or `return;` / `return nil`
- Find interface implementations where all methods are empty or return default values
- Find functions whose name suggests side effects (save, send, delete, update, notify) but whose body has no I/O operations
- Find middleware functions that call `next()` without doing anything

**Severity**: Critical if the stub is in a security path (authorization check that returns `true`). Major if in a data path. Moderate if in a non-critical feature path.

**Example of bad code**:
```python
class PaymentProcessor:
    def validate_card(self, card_number: str) -> bool:
        # TODO: implement card validation
        return True

    def process_payment(self, amount: float, card: dict) -> dict:
        # Process the payment through Stripe
        return {"status": "success", "transaction_id": "txn_placeholder"}

    def refund_payment(self, transaction_id: str) -> bool:
        pass
```

**Example of correct code**:
```python
class PaymentProcessor:
    def __init__(self, stripe_client: stripe.Client):
        self._stripe = stripe_client

    def validate_card(self, card_number: str) -> bool:
        try:
            token = self._stripe.tokens.create(card={'number': card_number, ...})
            return token is not None
        except stripe.error.CardError:
            return False

    def process_payment(self, amount: float, card: dict) -> PaymentResult:
        charge = self._stripe.charges.create(amount=int(amount * 100), currency='usd', source=card['token'])
        return PaymentResult(status=charge.status, transaction_id=charge.id)
```

**Why it's dangerous**: A validation function that always returns `true` means all input is accepted. A payment processor that returns fake success means the application believes payments went through when they didn't. These stubs pass happy-path tests and only fail in production.

---

## 4. Silent Failures

**Description**: Code that avoids crashes by removing error conditions rather than handling them. Instead of throwing an error when something goes wrong, the code returns a fake success response that matches the expected format. Different from fake error handling in that there is no try/catch at all -- the code simply never checks for error conditions.

**Detection heuristic**:
- Functions that interact with external systems (DB, API, filesystem) but have no error checking whatsoever
- Functions that return default values where null/undefined would be the natural result of a failed operation
- Missing null checks after operations that can return null (database lookups, array finds, map gets)
- API calls without response status checking
- File operations without existence checks
- Functions that always return a success-shaped object regardless of what happened internally

**Severity**: Major if data integrity is at risk. Moderate if the silent failure affects UX but not data.

**Example of bad code**:
```javascript
async function getUserPreferences(userId) {
  const prefs = await db.preferences.findOne({ userId });
  return {
    theme: prefs.theme || 'light',
    language: prefs.language || 'en',
    notifications: prefs.notifications || true
  };
}
// If prefs is null (user has no preferences record), this crashes with
// "Cannot read property 'theme' of null" -- or worse, if the AI added
// optional chaining: prefs?.theme || 'light' -- it silently returns
// defaults forever, even if the database query itself failed.
```

**Example of correct code**:
```javascript
async function getUserPreferences(userId) {
  const prefs = await db.preferences.findOne({ userId });
  if (!prefs) {
    // User has no preferences yet -- return documented defaults
    return { ...DEFAULT_PREFERENCES, isDefault: true };
  }
  return {
    theme: prefs.theme ?? DEFAULT_PREFERENCES.theme,
    language: prefs.language ?? DEFAULT_PREFERENCES.language,
    notifications: prefs.notifications ?? DEFAULT_PREFERENCES.notifications
  };
}
```

**Why it's dangerous**: The application appears to work correctly in development and testing because default values are often reasonable. In production, users' actual preferences, settings, or data are silently ignored. Debugging is extremely difficult because there are no errors in logs -- the system "works" from every observable metric.

---

## 5. Cargo-Cult Patterns

**Description**: Code that follows patterns from tutorials, blog posts, or training data without understanding why the pattern exists. The implementation is technically correct but inappropriate for the context -- either over-complicated for a simple task or using a pattern that solves a different problem than the one at hand.

**Detection heuristic**:
- Design patterns (Factory, Strategy, Observer, Singleton) used with only one concrete implementation
- Abstract base classes with a single subclass
- Middleware chains with a single middleware
- Configuration systems (with parsers, validators, environment-specific overrides) for 3-5 config values that never change
- Event systems for synchronous, linear flows
- Microservice-style architecture in a monolithic application
- Redux/state management boilerplate for a single component's local state
- ORMs introduced for applications with 1-2 simple queries

**Severity**: Minor for most cases (complexity but no harm). Moderate if the unnecessary complexity hides actual bugs or makes critical code hard to review.

**Example of bad code**:
```typescript
// Factory pattern for a single implementation
interface ILoggerFactory {
  createLogger(name: string): ILogger;
}

interface ILogger {
  log(message: string): void;
  error(message: string): void;
}

class ConsoleLoggerFactory implements ILoggerFactory {
  createLogger(name: string): ILogger {
    return new ConsoleLogger(name);
  }
}

class ConsoleLogger implements ILogger {
  constructor(private name: string) {}
  log(message: string) { console.log(`[${this.name}] ${message}`); }
  error(message: string) { console.error(`[${this.name}] ${message}`); }
}

// Used exactly once:
const loggerFactory = new ConsoleLoggerFactory();
const logger = loggerFactory.createLogger('app');
```

**Example of correct code**:
```typescript
// Just use a simple function:
function createLogger(name: string) {
  return {
    log: (message: string) => console.log(`[${name}] ${message}`),
    error: (message: string) => console.error(`[${name}] ${message}`),
  };
}

const logger = createLogger('app');
```

**Why it's dangerous**: Unnecessary abstraction increases cognitive load, making it harder to find real bugs during review. It also increases the surface area for mistakes -- more code means more potential for defects. Most critically, it signals that the code may not have been thoughtfully written, which reduces trust in the entire codebase.

---

## 6. Shallow Abstractions

**Description**: Wrapper functions or classes that add no value -- they exist only to add a layer of indirection. The wrapper does exactly what the underlying function does, with the same arguments, and provides no additional error handling, logging, validation, or transformation.

**Detection heuristic**:
- Functions that take the same parameters as the function they call and pass them through unchanged
- Classes with a single method that delegates entirely to another object
- Utility modules that re-export functions from another module without modification
- "Service" classes that are thin wrappers around a single ORM model
- API route handlers that call a controller that calls a service that calls a repository -- each doing nothing but forwarding

**Severity**: Minor in most cases. Moderate if the shallow abstraction hides the actual implementation from security review (e.g., a `sanitizeInput` wrapper that does not actually sanitize).

**Example of bad code**:
```javascript
// utils/api.js
export function fetchData(url) {
  return fetch(url);
}

export function postData(url, data) {
  return fetch(url, { method: 'POST', body: JSON.stringify(data) });
}

// Usage:
import { fetchData } from './utils/api';
const response = await fetchData('/api/users');
```

**Example of correct code**:
```javascript
// If you're going to wrap fetch, add actual value:
export async function apiFetch(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${getToken()}`,
      ...options.headers,
    },
  });
  if (!response.ok) {
    throw new ApiError(response.status, await response.text());
  }
  return response.json();
}
```

**Why it's dangerous**: Shallow abstractions create a false sense of encapsulation. Developers assume the wrapper provides value (error handling, auth, retry logic) when it doesn't. In security contexts, a function named `sanitizeInput` that just returns its argument is actively dangerous because reviewers assume it does what its name says.

---

## 7. Copy-Paste Structures

**Description**: Repeated code blocks with minor variations, often produced when an AI is asked to create multiple similar components or handlers. Each copy introduces a maintenance burden and a divergence risk -- when one copy is fixed, the others aren't.

**Detection heuristic**:
- Functions with 80%+ structural similarity (same shape, different variable names or string literals)
- Multiple React components with identical structure but different prop names
- API route handlers that repeat the same validation/auth/response pattern
- Database query functions that differ only in table name or field list
- Test files with copy-pasted test cases that differ only in input values

**Severity**: Minor for small duplications. Moderate if the duplication is in validation, authorization, or error handling logic (because a fix to one copy won't propagate to others).

**Example of bad code**:
```javascript
app.get('/api/users/:id', async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
    const user = await User.findById(req.params.id);
    if (!user) return res.status(404).json({ error: 'Not found' });
    res.json(user);
  } catch (err) { res.status(500).json({ error: 'Server error' }); }
});

app.get('/api/posts/:id', async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
    const post = await Post.findById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Not found' });
    res.json(post);
  } catch (err) { res.status(500).json({ error: 'Server error' }); }
});

// ... repeated 15 more times for every model
```

**Example of correct code**:
```javascript
function createGetByIdHandler(Model) {
  return async (req, res) => {
    try {
      if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
      const item = await Model.findById(req.params.id);
      if (!item) return res.status(404).json({ error: 'Not found' });
      res.json(item);
    } catch (err) {
      logger.error(`Failed to fetch ${Model.modelName}`, { id: req.params.id, error: err });
      res.status(500).json({ error: 'Server error' });
    }
  };
}

app.get('/api/users/:id', requireAuth, createGetByIdHandler(User));
app.get('/api/posts/:id', requireAuth, createGetByIdHandler(Post));
```

**Why it's dangerous**: When a bug is found in the pattern (missing authorization check, incorrect error response), it must be fixed in every copy. In practice, some copies get fixed and others don't, creating inconsistent behavior. The divergence is invisible until it causes a production issue.

---

## 8. Fabricated Comments

**Description**: Comments that describe code that doesn't exist, contradict the actual code, explain obvious things while ignoring non-obvious logic, or reference variables and functions that aren't defined. AI models generate comments based on what the code "should" do rather than what it actually does.

**Detection heuristic**:
- Comments that reference variable names, function names, or class names not present in the surrounding code
- Comments that describe a different algorithm or behavior than the code implements
- Comments like "// validate input" above code that does not validate input
- Comments like "// handle the error case" above an empty catch block
- Obvious comments: `i++; // increment i` while complex logic has no comments
- JSDoc/docstring parameter descriptions that don't match the actual parameters

**Severity**: Moderate if the comment describes security behavior that doesn't exist (e.g., "// sanitize user input" with no sanitization). Minor otherwise.

**Example of bad code**:
```python
def process_order(order_data):
    """Process an order, validate payment, check inventory,
    send confirmation email, and update analytics."""

    # Validate the order data
    order = Order(**order_data)

    # Process payment through Stripe
    order.status = 'completed'

    # Send confirmation email to customer
    db.session.add(order)
    db.session.commit()

    # Update inventory counts
    return order
```
The docstring claims 5 operations. The code does 2: create the order record and save it. No payment processing, no email, no analytics, no inventory update. Each comment describes the next step but the code for that step is missing.

**Example of correct code**:
```python
def create_order_record(order_data):
    """Create an order record in the database.

    NOTE: This only persists the order. Payment processing, inventory,
    and notifications are handled by the order processing pipeline
    triggered via the order.created event.
    """
    order = Order(**order_data)
    order.status = 'pending'  # Will be updated by payment processor
    db.session.add(order)
    db.session.commit()
    return order
```

**Why it's dangerous**: Misleading comments cause reviewers and future developers to believe the code does things it doesn't. If a comment says "validate input" and there's no validation, the next developer won't add validation because they think it's already there. This is worse than no comment at all.

---

## 9. Over-Engineering

**Description**: Unnecessary architectural complexity for the task at hand. AI models tend to generate "enterprise-grade" code for simple problems because their training data is dominated by large-project patterns. The result is code that is harder to read, harder to change, harder to debug, and more likely to contain bugs -- with no corresponding benefit.

**Detection heuristic**:
- Factory pattern with one concrete product
- Abstract class with one concrete subclass
- Strategy pattern with one strategy
- Observer/event system for a linear, synchronous flow
- Dependency injection container for a small application with 5-10 classes
- Configuration system (YAML parser, validator, environment merge) for 3-5 config values
- Plugin architecture with no plugins (or one built-in plugin)
- Service layer that mirrors the data layer 1:1 with no additional logic
- Generic type parameters that are always the same concrete type
- Builder pattern for objects with 2-3 fields

**Severity**: Minor for most cases. Moderate if the complexity obscures security-critical code or makes the codebase significantly harder to review.

**Example of bad code**:
```typescript
// For an app that sends exactly one type of notification (email):
interface NotificationStrategy { send(to: string, message: string): Promise<void>; }
interface NotificationFactory { create(type: string): NotificationStrategy; }
class EmailStrategy implements NotificationStrategy { /* ... */ }
class NotificationFactoryImpl implements NotificationFactory { /* ... */ }
class NotificationService {
  constructor(private factory: NotificationFactory) {}
  async notify(type: string, to: string, message: string) {
    const strategy = this.factory.create(type);
    await strategy.send(to, message);
  }
}
// 4 files, 3 interfaces, 3 classes, to send an email.
```

**Example of correct code**:
```typescript
async function sendEmail(to: string, subject: string, body: string): Promise<void> {
  await emailClient.send({ to, subject, body });
}
```

**Why it's dangerous**: Every layer of abstraction is a place where bugs can hide. Over-engineered code takes longer to review, which means reviewers are more likely to skim it. The complexity creates a cognitive burden that makes it easier to miss real issues. And when a bug is found, it takes longer to trace through the layers to fix it.

---

## 10. Under-Engineering

**Description**: Missing structure where it is genuinely needed. The opposite of over-engineering. Large files with mixed concerns, functions with too many responsibilities, deeply nested conditionals that obscure logic. AI models sometimes produce this when asked to "just make it work" or when generating code incrementally.

**Detection heuristic**:
- Files over 500 lines with multiple unrelated concerns (UI rendering + business logic + data access in one file)
- Functions over 100 lines
- Functions with 8+ parameters
- Nesting depth over 4 levels of conditionals/loops
- God objects: classes with 20+ methods or 15+ instance variables
- Single file that handles routing, validation, business logic, database access, and response formatting
- Mixed levels of abstraction (raw SQL next to high-level business logic in the same function)

**Severity**: Moderate if the lack of structure hides bugs or makes the code unreviewable. Minor if it's just messy but correct.

**Example of bad code**:
```javascript
// routes/api.js -- 800 lines, handles all API routes, all validation,
// all database queries, all response formatting, all error handling
app.post('/api/register', async (req, res) => {
  if (req.body.email) {
    if (req.body.email.includes('@')) {
      if (req.body.password) {
        if (req.body.password.length >= 8) {
          const existing = await db.query('SELECT id FROM users WHERE email = $1', [req.body.email]);
          if (existing.rows.length === 0) {
            const hash = await bcrypt.hash(req.body.password, 10);
            const result = await db.query('INSERT INTO users (email, password) VALUES ($1, $2) RETURNING id', [req.body.email, hash]);
            if (result.rows.length > 0) {
              const token = jwt.sign({ id: result.rows[0].id }, process.env.JWT_SECRET);
              res.json({ token });
            } else {
              res.status(500).json({ error: 'Failed to create user' });
            }
          } else {
            res.status(409).json({ error: 'Email already exists' });
          }
        } else {
          res.status(400).json({ error: 'Password too short' });
        }
      } else {
        res.status(400).json({ error: 'Password required' });
      }
    } else {
      res.status(400).json({ error: 'Invalid email' });
    }
  } else {
    res.status(400).json({ error: 'Email required' });
  }
});
```

**Example of correct code**:
```javascript
// Separate validation, business logic, and routing
const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

async function registerUser(email, password) {
  const existing = await userRepository.findByEmail(email);
  if (existing) throw new ConflictError('Email already registered');

  const hash = await bcrypt.hash(password, 10);
  const user = await userRepository.create({ email, password: hash });
  return authService.generateToken(user.id);
}

app.post('/api/register', validate(registerSchema), async (req, res, next) => {
  try {
    const token = await registerUser(req.body.email, req.body.password);
    res.json({ token });
  } catch (err) { next(err); }
});
```

**Why it's dangerous**: Deep nesting and mixed concerns make it nearly impossible to verify correctness during code review. Security checks buried in nested conditionals are easy to miss. Testing is difficult because the function does too many things. A change to one concern (e.g., validation logic) risks breaking another (e.g., database logic).

---

## 11. Inconsistent Patterns

**Description**: Different approaches to the same problem within the same codebase. AI-generated code in different sessions or from different prompts often uses different libraries, patterns, or conventions for identical tasks. This creates confusion about which pattern is "correct" and makes it impossible to apply uniform security or quality checks.

**Detection heuristic**:
- Multiple HTTP client libraries (fetch + axios + got in the same project)
- Mixed async patterns (callbacks + promises + async/await for the same type of operation)
- Some API routes use middleware for auth, others check auth inline
- Some error handling uses try/catch, others use .catch(), others use error-first callbacks
- Multiple state management approaches in the same frontend app
- Inconsistent import styles (default vs named imports for the same module)
- Some database queries use the ORM, others use raw SQL, for similar operations

**Severity**: Moderate if the inconsistency is in security-critical code (inconsistent auth checks means some routes may be unprotected). Minor for non-security inconsistencies.

**Example of bad code**:
```javascript
// File A: uses axios with async/await
const response = await axios.get('/api/users');

// File B: uses fetch with .then()
fetch('/api/users').then(res => res.json()).then(data => { ... });

// File C: uses a hand-rolled XMLHttpRequest wrapper
import { httpGet } from './utils/http';
const data = httpGet('/api/users', callback);
```

**Example of correct code**:
```javascript
// One HTTP client, consistently used everywhere:
import { apiClient } from '@/lib/api-client';

// File A:
const users = await apiClient.get('/api/users');

// File B:
const posts = await apiClient.get('/api/posts');
```

**Why it's dangerous**: Inconsistency means security fixes must be applied in multiple patterns. If you add auth headers to the axios interceptor, the fetch calls and the XMLHttpRequest wrapper don't get them. If you add retry logic, only one pattern benefits. Each pattern must be separately audited and maintained.

---

## 12. Deprecated/Outdated APIs

**Description**: AI models are trained on historical code and frequently generate code using deprecated APIs, old library versions, or outdated patterns. The code works today but may break on the next update, or it may miss security fixes available in newer APIs.

**Detection heuristic**:
- Compare API usage against the framework documentation for the version specified in package.json/requirements.txt/Cargo.toml
- Look for known deprecated patterns: `componentWillMount` (React), `new Buffer()` (Node.js), `urllib2` (Python 3), `mysql_*` functions (PHP), `java.util.Date` (Java 8+)
- Check for deprecation warnings in the framework/library's changelog for the installed version
- Look for patterns that have security-improved replacements (e.g., `crypto.createCipher` vs `crypto.createCipheriv`)

**Severity**: Major if the deprecated API has a security vulnerability that the replacement fixes. Moderate if the API will break in a future version. Minor if it's purely a style/convention update.

**Example of bad code**:
```javascript
// Node.js: Buffer constructor deprecated since v6, security risk
const buf = new Buffer(userInput);

// React: componentWillMount deprecated since 16.3, removed in 18
componentWillMount() {
  this.fetchData();
}

// Express: body-parser is built-in since Express 4.16
const bodyParser = require('body-parser');
app.use(bodyParser.json());
```

**Example of correct code**:
```javascript
const buf = Buffer.from(userInput);

useEffect(() => {
  fetchData();
}, []);

app.use(express.json());
```

**Why it's dangerous**: Deprecated APIs are deprecated for a reason -- often security vulnerabilities or correctness issues. `new Buffer(number)` allocates uninitialized memory that may contain sensitive data from other operations. Old React lifecycle methods have known issues with concurrent mode. Using deprecated APIs also signals that the code may not have been reviewed by someone familiar with the current version of the framework.

---

## 13. Optimistic External Assumptions

**Description**: Code that assumes external services (APIs, databases, file systems, third-party services) will always respond successfully, quickly, and with the expected data format. AI models generate the happy path and rarely include failure handling for external dependencies.

**Detection heuristic**:
- API calls without timeout configuration
- API calls without response status checking (assuming 200)
- API calls without error response body handling
- Database queries without connection error handling
- File operations without existence/permission checks
- Missing retry logic for transient failures
- No circuit breaker pattern for unreliable dependencies
- Destructuring API response bodies without checking if expected fields exist
- Missing handling for rate limit responses (429)

**Severity**: Major if the external dependency failure would cause data loss or security bypass. Moderate if it causes a poor user experience. Minor if it causes a clean crash with a good error message.

**Example of bad code**:
```javascript
async function getWeather(city) {
  const response = await fetch(`https://api.weather.com/v1/${city}`);
  const data = await response.json();
  return {
    temperature: data.main.temp,
    humidity: data.main.humidity,
    description: data.weather[0].description
  };
}
```
This code will crash if: the API returns a non-200 status, the response is not valid JSON, the response body doesn't have a `main` property, or `data.weather` is an empty array. All of these happen in production.

**Example of correct code**:
```javascript
async function getWeather(city) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);

  try {
    const response = await fetch(`https://api.weather.com/v1/${encodeURIComponent(city)}`, {
      signal: controller.signal
    });

    if (!response.ok) {
      throw new ExternalServiceError('weather-api', response.status, await response.text());
    }

    const data = await response.json();

    if (!data.main || !Array.isArray(data.weather) || data.weather.length === 0) {
      throw new ExternalServiceError('weather-api', 200, 'Unexpected response format');
    }

    return {
      temperature: data.main.temp,
      humidity: data.main.humidity,
      description: data.weather[0].description
    };
  } catch (error) {
    if (error.name === 'AbortError') {
      throw new ExternalServiceError('weather-api', 0, 'Request timed out');
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}
```

**Why it's dangerous**: External services are the most common source of production incidents. APIs go down, change their response format, return errors under load, or get rate-limited. Code that assumes success will crash, hang, or corrupt data when any of these inevitable conditions occur.

---

## 14. Fake Completeness

**Description**: Features that appear finished -- they have the right structure, the right names, the right number of functions -- but contain hardcoded paths, skipped edge cases, or only work with the happy-path input. AI models are optimized to produce "complete-looking" output, which means they will generate all the code to make a feature look done without actually handling all the cases.

**Detection heuristic**:
- Hardcoded values where dynamic values are needed (hardcoded user ID, hardcoded file path, hardcoded URL)
- Conditional branches with empty `else` blocks
- Switch statements without `default` cases
- Functions that only handle the first element of a collection
- Pagination that only fetches the first page
- Search that only matches exact strings
- Validation that checks type but not range, format, or business rules
- Permission checks that check authentication but not authorization
- Multi-step processes that implement step 1 and skip steps 2-N
- Internationalization that only handles English

**Severity**: Varies by context. Critical if the fake completeness is in security code (auth check that only checks one condition). Major if it causes functional failures on non-happy-path inputs. Moderate if edge cases are rare.

**Example of bad code**:
```python
def export_user_data(user_id):
    """Export all user data for GDPR compliance."""
    user = User.query.get(user_id)
    return {
        "profile": {
            "name": user.name,
            "email": user.email
        }
        # Missing: orders, comments, uploaded files, audit logs,
        # third-party data, payment history, support tickets...
    }
```
The function is named for GDPR compliance. It exports 2 fields. GDPR requires ALL personal data. This is fake completeness with legal liability.

**Example of correct code**:
```python
# At minimum, document what's included and what's missing:
GDPR_EXPORT_SOURCES = [
    ('profile', export_profile),
    ('orders', export_orders),
    ('comments', export_comments),
    ('files', export_uploaded_files),
    ('payments', export_payment_history),
    ('audit_log', export_audit_log),
    ('support_tickets', export_support_tickets),
]

def export_user_data(user_id):
    """Export all user data for GDPR compliance.

    Sources are defined in GDPR_EXPORT_SOURCES. Each source is independently
    exported and errors are collected (not raised) to ensure partial export
    on individual source failure.
    """
    results = {}
    errors = []
    for source_name, exporter in GDPR_EXPORT_SOURCES:
        try:
            results[source_name] = exporter(user_id)
        except Exception as e:
            errors.append({"source": source_name, "error": str(e)})
            logger.error(f"GDPR export failed for {source_name}", exc_info=True)

    return {"data": results, "errors": errors, "complete": len(errors) == 0}
```

**Why it's dangerous**: Fake completeness is the hardest AI slop pattern to detect because the code looks correct at a glance. It passes basic tests. It satisfies the ticket requirements as literally stated. But it fails in production because real users hit edge cases, and it fails compliance requirements because the feature doesn't actually do what it claims.

---

## Detection Priority

When reviewing a codebase, check for these patterns in this order:

1. **Hallucinated imports** (fast to check, immediately fatal)
2. **Placeholder stubs** in security paths (fast to check, critical impact)
3. **Fake error handling** in data mutation paths (high impact)
4. **Silent failures** in external integrations (high impact)
5. **Fake completeness** in security and compliance features (hard to detect, high impact)
6. **Optimistic external assumptions** (common, moderate impact)
7. **Fabricated comments** on security code (misleading, moderate impact)
8. **Inconsistent patterns** in auth/validation (security inconsistency)
9. **Deprecated APIs** with security implications (version-specific)
10. **Copy-paste structures** (maintenance risk)
11. **Over-engineering / under-engineering** (complexity/readability)
12. **Cargo-cult patterns** (maintenance, usually minor)
13. **Shallow abstractions** (cleanup, usually minor)
