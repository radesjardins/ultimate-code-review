# Chrome Extension Review Module

> Loaded when project matches: Manifest V3 Chrome extensions, Firefox/Edge compatible browser extensions

## Detection Heuristics

Activate this module when any of the following are found:
- `manifest.json` with `manifest_version`, `permissions`, `content_scripts`, or `background.service_worker`
- Presence of `popup.html`, `options.html`, `background.js`, `content.js` / `content-script.js`
- Directory structure: `src/background/`, `src/content/`, `src/popup/`, `src/options/`
- `package.json` scripts referencing `web-ext`, `crx`, or `chrome-extension` build tools
- References to `chrome.runtime`, `chrome.tabs`, `chrome.storage`, `browser.*` APIs

---

## Manifest Review

| Check | Severity | Description |
|-------|----------|-------------|
| `manifest_version` not 3 | HIGH | MV2 is deprecated; Chrome Web Store requires MV3 for new submissions |
| Overly broad `permissions` | HIGH | Each permission must be justified by actual usage in the codebase |
| Overly broad `host_permissions` | CRITICAL | `<all_urls>` or `*://*/*` grants access to every site; must be scoped to needed domains |
| Missing `content_security_policy` | MEDIUM | No explicit CSP; defaults may be insufficient, and intent should be documented |
| `externally_connectable` too broad | HIGH | Allows any website to message the extension; should be limited to specific domains |
| Missing `minimum_chrome_version` | LOW | Extension may break on older Chrome versions without warning |
| `web_accessible_resources` too broad | HIGH | Resources accessible to all origins; enables fingerprinting and potential exploitation |

### Manifest checklist:
```
[ ] manifest_version is 3
[ ] name, version, description are present and accurate
[ ] icons provided at 16, 48, 128 sizes
[ ] permissions list contains ONLY permissions that are used
[ ] host_permissions scoped to minimum required domains
[ ] content_security_policy explicitly defined
[ ] web_accessible_resources limited with matches array
```

---

## Permission Audit

### Every declared permission must map to code that uses it

| Permission | Justification needed | Severity if unused |
|------------|--------------------|--------------------|
| `tabs` | Must call `chrome.tabs` API beyond `activeTab` scope | HIGH |
| `activeTab` | Acceptable for action-triggered access to current tab | LOW |
| `storage` | Must use `chrome.storage.local` or `chrome.storage.sync` | MEDIUM |
| `cookies` | Must call `chrome.cookies` API; check if `fetch` would suffice | HIGH |
| `webRequest` | Must use `chrome.webRequest`; powerful, justify thoroughly | HIGH |
| `scripting` | Must use `chrome.scripting.executeScript` or similar | HIGH |
| `notifications` | Must call `chrome.notifications.create` | MEDIUM |
| `identity` | Must use `chrome.identity` for OAuth; check if needed | HIGH |
| `<all_urls>` | Almost never justified; narrow to specific match patterns | CRITICAL |
| `clipboardRead`/`clipboardWrite` | Must interact with clipboard; very sensitive | HIGH |
| `history` | Accesses full browsing history; extremely sensitive | CRITICAL |
| `bookmarks` | Full bookmark access; ensure it's core functionality | HIGH |

### Detection:
- Parse `manifest.json` permissions array
- Search codebase for `chrome.<permission-name>` usage
- Flag any permission declared but never used in code
- Flag `optional_permissions` that should be used instead of required permissions

---

## Content Scripts

| Check | Severity | Description |
|-------|----------|-------------|
| Match patterns too broad | HIGH | `matches: ["<all_urls>"]` or `*://*/*` injects into every page; scope to needed sites |
| DOM manipulation without sanitization | CRITICAL | `element.innerHTML = data` where data comes from page or API; XSS vector |
| No message validation | HIGH | Content script sends messages to background without structure; background trusts blindly |
| Accessing page JS context | HIGH | Content script trying to access page variables (isolated world boundary); using `window.postMessage` unsafely |
| Heavy DOM observers | MEDIUM | `MutationObserver` on `document.body` with `subtree: true` on all pages; performance impact |
| CSS conflicts | MEDIUM | Injected styles not scoped; extension CSS overrides page styles or vice versa |

### Detection patterns:
- `matches` array in manifest or `chrome.scripting.registerContentScripts` with broad patterns
- `document.body.innerHTML` or `.insertAdjacentHTML` in content scripts
- `MutationObserver` without `disconnect()` call path
- `window.addEventListener('message',` in content script without origin check

---

## Background Service Worker

| Check | Severity | Description |
|-------|----------|-------------|
| Global state reliance | HIGH | Variables stored in service worker global scope; lost when worker terminates (MV3 lifecycle) |
| Missing alarm for periodic tasks | MEDIUM | `setInterval` in service worker will not persist; use `chrome.alarms` instead |
| Synchronous blocking operations | HIGH | CPU-intensive work in service worker blocks all extension message handling |
| No error handling on API calls | HIGH | `chrome.tabs.get()` etc. called without checking `chrome.runtime.lastError` or using promise catch |
| Persistent connection keeping worker alive | MEDIUM | Long-lived `chrome.runtime.connect` ports keeping service worker alive unnecessarily |

### Detection patterns:
- Global `let`/`var` declarations at top of service worker file that store runtime state
- `setInterval(` or `setTimeout(` with delays >30s in service worker
- Missing `.catch()` on chrome API promise calls
- Missing `chrome.runtime.lastError` checks in callback patterns

---

## Storage

| Check | Severity | Description |
|-------|----------|-------------|
| Sensitive data in `chrome.storage.sync` | CRITICAL | Sync storage replicates to Google account; tokens/keys must use `storage.local` or better |
| Sensitive data in `chrome.storage.local` without encryption | HIGH | Local storage readable by any extension code; encrypt sensitive values |
| Using `localStorage` instead of `chrome.storage` | MEDIUM | `localStorage` is page-scoped and synchronous; `chrome.storage` is extension-wide and async |
| No storage quota management | MEDIUM | `chrome.storage.sync` has 100KB limit; no handling for `QUOTA_BYTES_PER_ITEM` errors |
| Storing large data without chunking | MEDIUM | Single items approaching quota limits; should chunk or use `storage.local` |

### Detection patterns:
- `chrome.storage.sync.set` with keys named `token`, `apiKey`, `secret`, `password`, `credential`
- `localStorage.setItem` in extension popup or options page
- No error callback on `chrome.storage` operations

---

## Message Passing

| Check | Severity | Description |
|-------|----------|-------------|
| No sender validation | CRITICAL | `chrome.runtime.onMessage` handler doesn't check `sender.id` or `sender.url` |
| No message type validation | HIGH | Handler processes any message shape; no type/action field check |
| External message handler open | CRITICAL | `chrome.runtime.onMessageExternal` without verifying `sender.id` against allowlist |
| Sensitive data in messages | HIGH | Passwords, tokens passed via messages (visible in devtools message log) |
| Missing `sendResponse` | MEDIUM | Async listener doesn't return `true` and call `sendResponse`; caller times out |

### Required pattern:
```javascript
// Background handler MUST validate:
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // 1. Check sender is from our extension
  if (sender.id !== chrome.runtime.id) return;
  // 2. Validate message structure
  if (!message.type || !ALLOWED_TYPES.includes(message.type)) return;
  // 3. Handle based on validated type
  // 4. Return true if async
});
```

---

## Web Accessible Resources

| Check | Severity | Description |
|-------|----------|-------------|
| Resources accessible to all origins | HIGH | `matches: ["<all_urls>"]` in web_accessible_resources; any page can load extension resources |
| JavaScript files exposed | CRITICAL | JS files in web_accessible_resources can be loaded by malicious pages to detect/interact with extension |
| No resources needed but section present | LOW | Empty or unnecessary web_accessible_resources declaration |

---

## Network Requests

| Check | Severity | Description |
|-------|----------|-------------|
| HTTP requests from extension | HIGH | Extension makes non-HTTPS requests; CSP should enforce but verify |
| No request timeout | MEDIUM | `fetch()` without `AbortController` timeout; request hangs indefinitely |
| Sensitive headers logged | HIGH | Authorization headers included in console.log or error reporting |
| CORS bypass via background | HIGH | Content script routes requests through background to bypass CORS; ensure this is necessary and secured |

---

## Security-Critical Patterns

| Check | Severity | Description |
|-------|----------|-------------|
| `eval()` anywhere in extension | CRITICAL | Forbidden by CSP and dangerous; flag unconditionally |
| `innerHTML` with dynamic content | CRITICAL | XSS in extension context is especially dangerous (elevated privileges) |
| Dynamic script creation | HIGH | `document.createElement('script')` with dynamic `src`; code injection vector |
| `chrome.scripting.executeScript` with string code | CRITICAL | Passing code as string instead of function; enables injection |
| Template literal HTML construction | HIGH | Building HTML strings with `${variable}` instead of DOM API |
| `new Function()` | CRITICAL | Equivalent to eval; CSP violation and code injection risk |

### Detection patterns:
- `eval(`, `new Function(`, `setTimeout(string,`, `setInterval(string,`
- `.innerHTML =` where right side contains variable
- `chrome.scripting.executeScript({ code:` or `{ func: new Function(`
- `document.createElement('script')` followed by `.src =` with variable

---

## Chrome Web Store Readiness

| Check | Severity | Description |
|-------|----------|-------------|
| Missing privacy policy | CRITICAL | Required for extensions that handle user data; rejection without it |
| Single purpose violation | HIGH | Extension does multiple unrelated things; CWS requires single clear purpose |
| Missing permissions justification | HIGH | CWS submission requires justification for each permission; document in advance |
| Missing screenshots | LOW | Store listing needs screenshots; prepare before submission |
| Undeclared remote code | CRITICAL | Loading JS from external URLs; prohibited in MV3, strict review in MV2 |
| Data collection undisclosed | CRITICAL | Collecting user data without disclosure in privacy policy and CWS listing |

---

## Common AI Slop

| Pattern | Severity | What to look for |
|---------|----------|------------------|
| `<all_urls>` permission | CRITICAL | Overly broad; AI defaults to requesting everything instead of minimum needed |
| Unused permissions | HIGH | `tabs`, `cookies`, `webRequest` declared but corresponding API never called |
| Content scripts on all sites | HIGH | `matches: ["<all_urls>"]` when extension only needs to run on specific sites |
| Tokens in `chrome.storage.sync` | CRITICAL | API keys or auth tokens in sync storage; synced to Google account across devices |
| No input sanitization in popup | HIGH | Popup page renders data from content script or storage without escaping |
| `innerHTML` in popup/options | HIGH | Building UI with `innerHTML` instead of DOM APIs or frameworks |
| Missing `chrome.runtime.lastError` checks | MEDIUM | Callback-based chrome API calls without error handling |
| Overly broad content script permissions | HIGH | Content script injected on all pages but only interacts with one site's DOM |
| Hardcoded extension IDs | MEDIUM | Other extension IDs hardcoded for message passing; should be configurable |
| Missing service worker lifecycle handling | HIGH | State stored in global vars; lost on service worker restart |

---

## Testing Requirements

| Requirement | Priority | Details |
|-------------|----------|---------|
| Extension lifecycle tests | REQUIRED | Install, enable, disable, update scenarios work correctly |
| Permission boundary tests | REQUIRED | Extension only accesses what permissions allow; fails gracefully if optional permission denied |
| Content script isolation | REQUIRED | Content script doesn't leak data between tabs or to page context |
| Message passing validation | REQUIRED | Invalid messages are rejected; only expected message types processed |
| Popup/options functionality | REQUIRED | UI renders correctly, user settings persist, form validation works |
| Cross-browser compatibility | RECOMMENDED | Test on Chrome, Firefox (if targeting), Edge |
| Storage migration tests | RECOMMENDED | Upgrade scenarios preserve user data correctly |
| Error scenario tests | REQUIRED | Network failure, API errors, storage full handled gracefully |

### Testing tools:
- `puppeteer` with extension loading for E2E
- `jest` / `vitest` for unit tests on background and content script logic
- `web-ext lint` for manifest validation
- Chrome Extension Test Framework for integration tests
