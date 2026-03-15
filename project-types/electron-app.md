# Electron App Review Module

> Loaded when project matches: Electron, Tauri

## Detection Heuristics

Activate this module when any of the following are found:
- `package.json` contains `electron`, `electron-builder`, `electron-forge`, `@electron/`
- `package.json` contains `@tauri-apps/api`, `@tauri-apps/cli`
- Presence of `electron-builder.yml`, `forge.config.js`, `tauri.conf.json`
- Presence of `main.js`/`main.ts` with `BrowserWindow`, `app.on('ready')`
- Directories: `src/main/`, `src/renderer/`, `src/preload/`
- Presence of `preload.js`/`preload.ts` files

---

## Process Model

| Check | Severity | Description |
|-------|----------|-------------|
| No preload script | CRITICAL | Main process APIs exposed directly to renderer; must use preload + contextBridge |
| Main process handles rendering logic | HIGH | UI logic in main process; should be in renderer with IPC for Node.js operations |
| Renderer accesses Node.js directly | CRITICAL | `require('fs')` or `require('child_process')` in renderer code; must go through preload |
| Preload exposes too much | HIGH | Preload script exposes broad APIs like `ipcRenderer` directly instead of specific functions |
| Missing contextBridge | CRITICAL | Preload script sets `window.api` without using `contextBridge.exposeInMainWorld` |

### Detection patterns:
- `BrowserWindow` creation without `preload` path in `webPreferences`
- `require('fs')`, `require('path')`, `require('child_process')` in files under `renderer/` or loaded by `BrowserWindow`
- Preload file contains `contextBridge.exposeInMainWorld('api', { ipcRenderer })` (exposes whole IPC)
- Preload should expose specific functions: `contextBridge.exposeInMainWorld('api', { readFile: (path) => ipcRenderer.invoke('read-file', path) })`

### Correct preload pattern:
```javascript
// GOOD: Expose specific functions, not raw APIs
contextBridge.exposeInMainWorld('api', {
  readFile: (filePath) => ipcRenderer.invoke('read-file', filePath),
  saveFile: (filePath, content) => ipcRenderer.invoke('save-file', filePath, content),
  onUpdateAvailable: (callback) => ipcRenderer.on('update-available', callback),
});

// BAD: Exposes raw IPC, renderer can invoke any channel
contextBridge.exposeInMainWorld('api', {
  send: (channel, data) => ipcRenderer.send(channel, data),
  invoke: (channel, ...args) => ipcRenderer.invoke(channel, ...args),
});
```

---

## IPC Security

| Check | Severity | Description |
|-------|----------|-------------|
| No channel allowlist | CRITICAL | IPC handler accepts any channel name; renderer can invoke arbitrary main process functions |
| Missing argument validation | HIGH | `ipcMain.handle` trusts arguments from renderer without validation |
| Sensitive data over IPC | MEDIUM | Passwords, tokens passed via IPC; consider if it can be handled entirely in main process |
| Missing error handling in IPC | HIGH | `ipcMain.handle` throws unhandled error; crashes main process or leaks error details |
| `ipcRenderer.send` for request-response | MEDIUM | Using `send`/`on` pattern instead of `invoke`/`handle`; no built-in error propagation |
| IPC from untrusted content | CRITICAL | WebView or loaded external page can send IPC messages; must validate source window |

### Detection patterns:
- `ipcMain.on('*',` or dynamic channel names in IPC handlers
- `ipcMain.handle` callbacks that don't validate `event.sender` or argument types
- IPC channel names that suggest sensitive operations without validation: `execute-command`, `run-shell`, `read-file`
- `event.sender` not checked in IPC handlers (could come from any window, including devtools)

### IPC validation pattern:
```javascript
ipcMain.handle('read-file', async (event, filePath) => {
  // 1. Validate sender is expected window
  if (event.sender !== mainWindow.webContents) {
    throw new Error('Unauthorized sender');
  }
  // 2. Validate arguments
  if (typeof filePath !== 'string') throw new Error('Invalid path');
  // 3. Scope file access
  const resolved = path.resolve(filePath);
  if (!resolved.startsWith(allowedDir)) throw new Error('Access denied');
  // 4. Perform operation
  return fs.readFile(resolved, 'utf-8');
});
```

---

## Node.js in Renderer

| Check | Severity | Description |
|-------|----------|-------------|
| `nodeIntegration: true` | CRITICAL | MUST be `false`. Enables `require()` in renderer; any XSS = full system compromise |
| `contextIsolation: false` | CRITICAL | MUST be `true`. Without it, preload and renderer share scope; renderer can override preload |
| `sandbox: false` | HIGH | Should be `true` or omitted (defaults to true in recent Electron). Disabling removes OS-level sandbox |
| `webSecurity: false` | CRITICAL | Disables same-origin policy; renderer can load any URL, make any request |
| `allowRunningInsecureContent: true` | CRITICAL | Allows HTTP content on HTTPS pages; MITM can inject code |

### Detection patterns:
Search for `new BrowserWindow` and check `webPreferences`:
```javascript
// FLAG ALL OF THESE:
nodeIntegration: true       // CRITICAL
contextIsolation: false     // CRITICAL
webSecurity: false          // CRITICAL
sandbox: false              // HIGH
allowRunningInsecureContent: true  // CRITICAL
experimentalFeatures: true  // MEDIUM
enableRemoteModule: true    // CRITICAL (deprecated, still dangerous)
```

---

## WebPreferences Audit

### Complete checklist for every BrowserWindow:
```
[ ] nodeIntegration: false (or omitted, defaults to false)
[ ] contextIsolation: true (or omitted, defaults to true in Electron 12+)
[ ] sandbox: true (or omitted, defaults to true in Electron 20+)
[ ] webSecurity: true (or omitted, defaults to true)
[ ] allowRunningInsecureContent: false (or omitted)
[ ] experimentalFeatures: false (or omitted)
[ ] enableRemoteModule: false (or omitted)
[ ] preload: points to a valid preload script
[ ] If loading remote content: set appropriate session permissions
```

---

## Protocol Handling

| Check | Severity | Description |
|-------|----------|-------------|
| Custom protocol allows file access | CRITICAL | Custom protocol handler serves arbitrary local files; must restrict to app directory |
| `file://` not restricted | HIGH | Renderer can navigate to `file://` URLs; reads local file system |
| Deep link input not validated | CRITICAL | App handles `myapp://` URLs; parameters used without sanitization |
| `registerFileProtocol` too broad | HIGH | File protocol serves from root or home directory instead of app resources only |
| `shell.openExternal` without URL validation | CRITICAL | Opens any URL in system browser; `javascript:`, `file:`, or `data:` URLs are dangerous |

### Detection patterns:
- `protocol.registerFileProtocol` serving from `__dirname` parent or root
- `shell.openExternal(url)` where `url` is from renderer without validation
- Missing URL scheme check: must verify `url.startsWith('https://')` before `shell.openExternal`
- `app.setAsDefaultProtocolClient` without input validation handler

### Safe shell.openExternal:
```javascript
function safeOpenExternal(url) {
  const parsed = new URL(url);
  if (!['https:', 'http:'].includes(parsed.protocol)) {
    throw new Error(`Blocked opening URL with protocol: ${parsed.protocol}`);
  }
  // Optionally: check against domain allowlist
  shell.openExternal(url);
}
```

---

## Native Access

| Check | Severity | Description |
|-------|----------|-------------|
| Unrestricted file system access | HIGH | Main process reads/writes anywhere on disk; scope to app data directory |
| No dialog for file operations | MEDIUM | File operations happen silently; user should confirm via dialog for non-app files |
| Shell command execution | CRITICAL | `child_process.exec` in main process with renderer-provided arguments |
| Native module without audit | HIGH | Native `.node` addon included; has full system access, audit for safety |
| Clipboard access unrestricted | MEDIUM | Renderer can read clipboard at any time without user action |

---

## Auto-Update

| Check | Severity | Description |
|-------|----------|-------------|
| Update over HTTP | CRITICAL | Update downloaded over HTTP; MITM can serve malicious update |
| Missing code signature verification | CRITICAL | Update applied without verifying publisher signature; tampered update runs |
| Update server hardcoded | MEDIUM | Update URL hardcoded; if domain expires, attacker can serve malicious updates |
| No update notification | LOW | App updates silently without informing user; unexpected behavior changes |
| Downgrade not prevented | HIGH | Older version can be installed via update mechanism; attacker serves old vulnerable version |

### Detection patterns:
- `autoUpdater.setFeedURL` with HTTP URL (not HTTPS)
- Missing `electron-updater` code signing configuration
- No certificate/signature verification in update flow
- Tauri: check `tauri.conf.json` updater configuration for HTTPS and pubkey

---

## Packaging

| Check | Severity | Description |
|-------|----------|-------------|
| ASAR not enabled | MEDIUM | App resources not packaged in ASAR archive; source code directly readable on disk |
| Missing code signing | HIGH | App not signed; OS warnings on launch, no tamper detection |
| Missing notarization (macOS) | HIGH | macOS app not notarized; Gatekeeper blocks launch |
| Dev dependencies in production | HIGH | `node_modules` in packaged app includes dev dependencies; bloated bundle |
| Source maps in production | MEDIUM | `.map` files included in package; exposes source code |
| Hardcoded dev URLs | HIGH | `loadURL('http://localhost:3000')` not gated to development mode |

### Detection patterns:
- `electron-builder.yml` or `forge.config.js` missing signing configuration
- No `afterSign` hook for notarization in build config
- `mainWindow.loadURL` with `localhost` without `isDev` check
- Missing `asar: true` in builder config (usually default, but verify)

---

## Performance

| Check | Severity | Description |
|-------|----------|-------------|
| Large IPC payloads | HIGH | Megabytes of data sent over IPC; use file path or shared buffer instead |
| Main process blocking | CRITICAL | Synchronous file I/O or computation in main process; freezes all windows |
| Renderer memory leak | HIGH | BrowserWindow not destroyed properly; detached DOM nodes, unreleased listeners |
| Too many BrowserWindows | MEDIUM | Creating new window for each task; reuse windows or use single-window with views |
| No lazy loading of windows | MEDIUM | All windows created at startup even if user may never open them |

### Detection patterns:
- `ipcMain.handle` callbacks with synchronous operations: `fs.readFileSync`, `JSON.parse` of large files
- `ipcRenderer.send` with large objects (>1MB) serialized per message
- `BrowserWindow` created but never `.destroy()`ed or `.close()`d
- Missing `win.on('closed', () => { win = null })` cleanup pattern

---

## Common AI Slop

| Pattern | Severity | What to look for |
|---------|----------|------------------|
| `nodeIntegration: true` | CRITICAL | AI defaults to enabling Node in renderer for convenience; disables core security model |
| `contextIsolation: false` | CRITICAL | Paired with `nodeIntegration: true`; "make it work" approach ignoring security |
| `shell.openExternal` unvalidated | CRITICAL | URL from renderer passed directly to `shell.openExternal` without protocol check |
| Full file system access | HIGH | IPC handler reads/writes any path the renderer requests; no scoping to app directory |
| All IPC channels exposed | HIGH | Preload wraps `ipcRenderer.invoke` generically instead of exposing specific functions |
| `webSecurity: false` for dev convenience | CRITICAL | CORS disabled "because it was causing errors during development"; left in production |
| Synchronous IPC | MEDIUM | `ipcRenderer.sendSync` used for convenience; blocks renderer main thread |
| Missing window ready check | MEDIUM | `mainWindow.webContents.send` without checking window is ready; messages lost |
| Dev tools enabled in production | MEDIUM | `mainWindow.webContents.openDevTools()` not gated to development mode |
| Hardcoded window dimensions | LOW | Fixed pixel sizes without considering display scaling or screen resolution |

---

## Testing Requirements

| Requirement | Priority | Details |
|-------------|----------|---------|
| IPC boundary tests | REQUIRED | Every IPC channel tested: valid input, invalid input, unauthorized sender |
| Security boundary tests | REQUIRED | Verify renderer cannot access Node.js APIs, file system, or shell directly |
| Window lifecycle tests | REQUIRED | Create, destroy, minimize, restore, multi-window interactions work correctly |
| Cross-platform tests | REQUIRED | Test on Windows, macOS, Linux; path handling, native features, UI rendering |
| Update flow tests | RECOMMENDED | Auto-update check, download, apply cycle works without data loss |
| Deep link tests | REQUIRED | Custom protocol URLs validated and handled correctly; malicious URLs rejected |
| Crash recovery tests | RECOMMENDED | App recovers gracefully from renderer crash; user data not lost |
| Performance benchmarks | RECOMMENDED | Startup time, memory usage, IPC throughput measured and tracked |

### Testing tools:
- `@electron/remote` for test automation (carefully scoped)
- `spectron` (legacy) or `playwright` with Electron support
- Tauri: `tauri-driver` for WebDriver-based testing
- Unit tests for main process logic with `jest` / `vitest` (no Electron runtime needed)
