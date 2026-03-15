# Mobile App Review Module

> Loaded when project matches: React Native, Flutter, Capacitor, Ionic, native iOS/Android

## Detection Heuristics

Activate this module when any of the following are found:
- `package.json` contains `react-native`, `expo`, `@capacitor/core`, `@ionic/`
- `pubspec.yaml` present (Flutter/Dart)
- Presence of `android/` and `ios/` directories
- `app.json` with `expo` configuration
- `capacitor.config.ts` or `capacitor.config.json` present
- `*.xcodeproj`, `*.xcworkspace`, `Podfile` (iOS native)
- `build.gradle`, `AndroidManifest.xml` (Android native)
- `Info.plist`, `AppDelegate.swift`/`AppDelegate.m` files

---

## Platform-Specific Concerns

### iOS
| Check | Severity | Description |
|-------|----------|-------------|
| App Transport Security disabled | HIGH | `NSAllowsArbitraryLoads` set to YES; allows HTTP connections; App Store review flag |
| Missing privacy usage descriptions | CRITICAL | `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription` etc. missing; crash on access |
| Background mode unjustified | HIGH | Background modes enabled in capabilities but not functionally needed; App Store rejection |
| Missing entitlements | HIGH | Push notifications, keychain sharing, or app groups used without corresponding entitlement |
| UIWebView usage | CRITICAL | UIWebView is deprecated and rejected by App Store; must use WKWebView |

### Android
| Check | Severity | Description |
|-------|----------|-------------|
| `android:exported` not set | HIGH | Activities/services missing explicit `exported` attribute; required for API 31+ |
| `android:allowBackup="true"` | HIGH | User data extractable via `adb backup`; disable or encrypt sensitive data |
| Missing `android:networkSecurityConfig` | MEDIUM | No network security config; unclear what domains/certificates are trusted |
| `cleartext` traffic permitted | HIGH | `android:usesCleartextTraffic="true"` or missing network security config allowing HTTP |
| Targeting old SDK | MEDIUM | `targetSdkVersion` below current requirement; Google Play rejection |

### Detection patterns:
- Search `Info.plist` for `NSAllowsArbitraryLoads`
- Search `AndroidManifest.xml` for `exported`, `allowBackup`, `usesCleartextTraffic`
- Check `build.gradle` for `targetSdkVersion` and `minSdkVersion`
- React Native: check `ios/` and `android/` config files for these settings

---

## Navigation

| Check | Severity | Description |
|-------|----------|-------------|
| Deep link parameter injection | CRITICAL | Deep link URL parameters used directly in queries or rendered without validation |
| Missing deep link scheme validation | HIGH | App handles `myapp://` but doesn't validate the path/host component |
| Universal link misconfiguration | HIGH | `apple-app-site-association` or `assetlinks.json` missing or misconfigured |
| Stack state manipulation | MEDIUM | User can navigate to screen out of expected sequence via deep link; skips validation steps |
| Back button data loss | MEDIUM | Android back button discards unsaved form data without confirmation |
| Auth state not checked on navigation | HIGH | Deep link navigates directly to authenticated screen; auth check happens too late |

### Detection patterns:
- Deep link handler that extracts params and navigates: `navigation.navigate(route, { id: linkParams.id })`
- Missing URL validation in `Linking.addEventListener` callback
- React Navigation: `linking` config with parameterized routes but no `parse` function to validate params
- Flutter: `onGenerateRoute` without parameter validation

---

## Data Storage

| Check | Severity | Description |
|-------|----------|-------------|
| Tokens in AsyncStorage/SharedPreferences | CRITICAL | Auth tokens in plaintext storage; accessible via device backup or root |
| Sensitive data not using Keychain/Keystore | CRITICAL | Passwords, tokens, encryption keys stored outside secure enclave |
| Unencrypted local database | HIGH | SQLite database with sensitive data not using SQLCipher or equivalent encryption |
| Sensitive data in app logs | HIGH | Tokens, user data logged via `console.log` or native logging; accessible via system logs |
| Credentials in Redux/state persist | CRITICAL | Auth tokens persisted to disk via Redux Persist without encryption transform |
| Cache not cleared on logout | HIGH | Sensitive data remains in caches, images, or temp files after user logs out |

### Detection patterns:
- `AsyncStorage.setItem('token',` or `AsyncStorage.setItem('user',` (React Native)
- `SharedPreferences.edit().putString("token",` (Android)
- `UserDefaults.standard.set(token,` (iOS - should use Keychain)
- `redux-persist` configuration without `transforms` that encrypt sensitive slices
- Missing cleanup in logout handler: search for all storage writes and verify matching deletes

### Secure storage libraries:
- **React Native**: `react-native-keychain`, `expo-secure-store`
- **Flutter**: `flutter_secure_storage`
- **Capacitor**: `@capacitor/preferences` for non-sensitive; native keychain plugin for sensitive
- **iOS native**: `Keychain Services` API
- **Android native**: `EncryptedSharedPreferences`, `AndroidKeyStore`

---

## Network

| Check | Severity | Description |
|-------|----------|-------------|
| No certificate pinning | HIGH | App trusts any valid certificate; MITM with rogue CA possible |
| No proxy detection | MEDIUM | App doesn't detect proxy/MITM for sensitive operations |
| No offline mode handling | HIGH | App crashes or shows blank screen when network is unavailable |
| Missing request retry logic | MEDIUM | Network requests fail permanently on transient errors; no retry with backoff |
| Background sync without battery consideration | MEDIUM | Sync runs frequently in background; drains battery |
| API URL hardcoded per environment | HIGH | `if (DEV) url = 'http://localhost'` instead of environment configuration |

### Detection patterns:
- No TrustKit, ssl-pinning, or certificate pinning configuration in native code
- Missing `NetInfo` or connectivity check before network operations
- `fetch(url)` without `.catch()` or try-catch; unhandled network error
- Multiple API base URLs selected by environment flag in source code
- Missing `@react-native-community/netinfo` or equivalent dependency

---

## Push Notifications

| Check | Severity | Description |
|-------|----------|-------------|
| Token sent over HTTP | CRITICAL | Push notification token sent to backend without HTTPS |
| Token stored insecurely | HIGH | Push token stored in AsyncStorage alongside auth token; different sensitivity levels mixed |
| Notification payload has sensitive data | HIGH | Push notification content visible on lock screen; don't include sensitive information |
| Deep link in notification not validated | HIGH | Notification tap handler navigates to URL/route from payload without validation |
| Missing token refresh handling | MEDIUM | Push token can rotate; app doesn't handle refresh and re-register with backend |
| Silent push for sensitive operations | MEDIUM | Silent push triggers data operations without user awareness |

### Detection patterns:
- Push token registration making HTTP (not HTTPS) request
- Notification handler that extracts URL from payload and calls `Linking.openURL` directly
- Missing `onTokenRefresh` or equivalent registration
- Notification payload containing user PII in `title` or `body` fields

---

## Permissions

| Check | Severity | Description |
|-------|----------|-------------|
| Permissions requested at launch | HIGH | All permissions requested immediately on first launch; should request in context |
| Missing permission rationale | MEDIUM | No explanation shown to user before permission prompt; lower grant rate and poor UX |
| No graceful degradation | HIGH | Feature crashes or shows error if permission denied; should offer reduced functionality |
| Unused permission declared | HIGH | Permission in manifest/plist but never actually requested in code |
| Location always vs when-in-use | HIGH | `Always` location requested when `WhenInUse` would suffice; App Store review flag |
| Camera/microphone without clear purpose | HIGH | Permission requested but unclear to user why; privacy concern |

### Detection patterns:
- Permission requests in app startup/initialization code instead of feature-specific code
- `PermissionsAndroid.request` without checking result and handling denial
- `CLLocationManager.requestAlwaysAuthorization` when app only needs foreground location
- `NSLocationAlwaysAndWhenInUseUsageDescription` in Info.plist for app that only uses map display

---

## Performance

| Check | Severity | Description |
|-------|----------|-------------|
| Main thread blocking | CRITICAL | Heavy computation, JSON parsing, or image processing on UI thread |
| FlatList without keyExtractor | MEDIUM | React Native list without `keyExtractor`; triggers full re-render on data change |
| FlatList without getItemLayout | MEDIUM | Dynamic height items without `getItemLayout`; scroll position jumps |
| Images not cached/resized | HIGH | Full-resolution images loaded for thumbnails; memory pressure and slow rendering |
| Too many re-renders | HIGH | Component re-renders on every keystroke or scroll; missing memoization |
| Large bundle size | HIGH | App bundle includes unused assets, unoptimized images, unused libraries |
| Startup time issues | HIGH | Heavy initialization on app launch; lazy-load non-essential modules |

### Detection patterns:
- `JSON.parse` of large payload in component render or on main thread
- `FlatList` without `keyExtractor`, `getItemLayout`, or `windowSize` optimization
- `Image` component with remote URL without `resizeMode` and caching configuration
- Missing `React.memo`, `useMemo`, `useCallback` on components in lists
- Flutter: missing `const` constructors, unnecessary `setState` calls
- Large `import` blocks at top of entry file; no dynamic `import()` usage

---

## Native Modules/Bridge

| Check | Severity | Description |
|-------|----------|-------------|
| Bridge type mismatch | HIGH | JavaScript sends string but native expects number; silent conversion or crash |
| Missing error handling across bridge | HIGH | Native error not propagated to JS; promise hangs or rejects with useless error |
| Thread safety | HIGH | Native module accessed from multiple JS calls concurrently without synchronization |
| Memory leak across bridge | HIGH | Native objects retained but JS reference released; or vice versa |
| Excessive bridge traffic | MEDIUM | High-frequency bridge calls (scroll events, animations); should use native driver |

### Detection patterns:
- React Native: `NativeModules.ModuleName.method()` without `.catch()` or try-catch
- Native module method parameters don't match between JS call and native implementation
- `Animated` values without `useNativeDriver: true` when possible
- Flutter: `MethodChannel` calls without error handling on either side

---

## Build Configuration

| Check | Severity | Description |
|-------|----------|-------------|
| Debug configuration in release | CRITICAL | Debug logging, dev menus, or test endpoints enabled in release build |
| Missing ProGuard/R8 rules | HIGH | Android release build without code shrinking; larger APK, unobfuscated code |
| Missing code signing | CRITICAL | Release build not signed; cannot be installed or published |
| Missing bundle splitting | MEDIUM | Hermes/V8 bundle not optimized; loading time affected |
| Dev dependencies in production | HIGH | Test frameworks, debugging tools included in production bundle |
| Source maps shipped | MEDIUM | JavaScript source maps included in app bundle; code visible if extracted |

### Detection patterns:
- `__DEV__` checks missing around debug-only code
- `build.gradle` release block missing `minifyEnabled true`
- Missing `proguard-rules.pro` with custom rules for libraries
- React Native: `hermes` not enabled when it should be (performance)
- Expo: `app.json` missing production-specific configuration

---

## Common AI Slop

| Pattern | Severity | What to look for |
|---------|----------|------------------|
| Tokens in AsyncStorage | CRITICAL | `AsyncStorage.setItem('token',` or `setItem('user',`; use secure storage |
| Missing permission pre-checks | HIGH | Camera/location used without checking permission status first; crash on denied |
| Synchronous main thread operations | HIGH | `JSON.parse`, file I/O, or heavy computation in render or event handler |
| Hardcoded API URLs per environment | HIGH | `const API_URL = __DEV__ ? 'http://localhost:3000' : 'https://prod.com'` in source |
| No offline handling | HIGH | `fetch` without connectivity check or error handling; blank screen when offline |
| Console.log in production | MEDIUM | Debug logging left in production code; visible in device logs, performance impact |
| Platform-specific code missing | MEDIUM | `Platform.OS === 'ios'` checks needed but missing; Android-specific behavior assumed |
| Hardcoded dimensions | MEDIUM | `width: 375` or `height: 812` instead of `Dimensions.get` or responsive layout |
| Missing loading states | HIGH | Data fetching without loading indicator; user sees blank screen or stale data |
| Navigation without auth check | HIGH | Authenticated screen reachable via deep link without auth state verification |

---

## Testing Requirements

| Requirement | Priority | Details |
|-------------|----------|---------|
| Platform-specific behavior tests | REQUIRED | Test iOS-specific and Android-specific code paths and UI rendering |
| Permission flow tests | REQUIRED | Grant, deny, and revoke scenarios for each permission |
| Deep link tests | REQUIRED | Valid deep links navigate correctly; malicious deep links are rejected |
| Offline mode tests | REQUIRED | App remains functional (degraded) when network is unavailable |
| Secure storage tests | REQUIRED | Sensitive data written to Keychain/Keystore, not plaintext storage |
| Navigation tests | REQUIRED | Back button, deep link, notification tap navigation all work correctly |
| Performance benchmarks | RECOMMENDED | Startup time, list scroll FPS, memory usage measured and tracked |
| Device matrix tests | RECOMMENDED | Test on small screens, large screens, tablets, different OS versions |

### Testing tools:
- **React Native**: `@testing-library/react-native`, Detox (E2E), Appium
- **Flutter**: `flutter_test`, `integration_test`, `patrol`
- **Capacitor/Ionic**: Cypress with mobile viewports, Appium for native
- **iOS native**: XCTest, XCUITest
- **Android native**: Espresso, UI Automator, Robolectric
