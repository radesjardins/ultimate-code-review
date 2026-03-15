# Web Application Review Module

> Loaded when project matches: React, Next.js, Vue, Nuxt, Angular, Svelte, SvelteKit, Astro, Remix

## Detection Heuristics

Activate this module when any of the following are found:
- `package.json` contains `react`, `react-dom`, `next`, `vue`, `nuxt`, `@angular/core`, `svelte`, `astro`, `@remix-run/react`
- Presence of `next.config.*`, `nuxt.config.*`, `angular.json`, `svelte.config.*`, `astro.config.*`
- Directories: `src/components/`, `src/pages/`, `src/routes/`, `app/` (Next.js app router)
- File extensions: `.jsx`, `.tsx`, `.vue`, `.svelte`, `.astro`

---

## Framework-Specific Patterns

### SSR vs CSR Concerns
| Check | Severity | Description |
|-------|----------|-------------|
| Server component using client APIs | CRITICAL | `window`, `document`, `localStorage` accessed in server components/SSR context without guards |
| Missing `"use client"` directive | HIGH | Next.js 13+ component uses hooks or browser APIs without client directive |
| Hydration mismatch sources | HIGH | Server and client render different output (Date.now(), Math.random(), conditional rendering on `typeof window`) |
| Data fetching in wrong layer | MEDIUM | Client-side fetch for data that should be server-fetched (SEO content, initial page data) |
| Missing Suspense boundaries | MEDIUM | Async server components or lazy-loaded components without Suspense fallback |

### What to look for:
- `useEffect` used for data that should come from `getServerSideProps`, `loader`, or server components
- `typeof window !== 'undefined'` guards that cause hydration mismatch instead of using `useEffect` for client-only logic
- Async operations in component body outside of proper data-fetching patterns (loader, server component, `use()`)
- Framework data fetching bypassed in favor of raw `fetch` in `useEffect`

---

## State Management

### Common Pitfalls
| Check | Severity | Description |
|-------|----------|-------------|
| Prop drilling beyond 3 levels | MEDIUM | Props passed through 3+ intermediate components that don't use them |
| Stale closure in useEffect/useCallback | HIGH | Missing dependencies in hooks array; captured variable never updates |
| Unnecessary re-renders from object/array literals | MEDIUM | `style={{}}`, `options={[]}`, or `callback={() => {}}` in JSX creating new references every render |
| Global state for local concerns | LOW | Redux/Zustand/Pinia store used for state that belongs to one component or route |
| Mutating state directly | CRITICAL | Direct mutation of state object/array instead of immutable update (React/Vue reactivity breakage) |
| Derived state stored separately | MEDIUM | Value computable from existing state stored as independent state, creating sync bugs |

### Detection patterns:
- Search for `useState` whose setter is passed down 3+ component layers
- `useEffect` or `useCallback` with empty `[]` that references props or outer state
- Redux actions dispatched and immediately read back in same component (round-trip for local state)
- `state.items.push()` or `state.obj.key = val` in React (should use spread/map/filter)

---

## Routing

### Client-Side Routing Security
| Check | Severity | Description |
|-------|----------|-------------|
| Unprotected routes | CRITICAL | Routes with sensitive content lack auth guards; user can navigate directly via URL |
| Auth check only in UI | HIGH | Auth guard hides link/button but route itself renders content without checking auth state |
| Redirect loop potential | MEDIUM | Auth redirect goes to page that redirects unauthenticated users, creating infinite loop |
| Route params unsanitized | HIGH | Route parameters (`/user/:id`) used directly in queries or rendered without validation |

### SSR Routing
- Server-side redirects should return proper 3xx status, not client-side `router.push`
- Protected API routes must validate session/token server-side, not rely on middleware alone
- Dynamic route segments must be validated against expected format before database lookup

---

## Build and Bundling

| Check | Severity | Description |
|-------|----------|-------------|
| No code splitting | HIGH | Single bundle >500KB; missing `lazy()`, `defineAsyncComponent`, dynamic `import()` |
| Barrel file re-exports everything | MEDIUM | `index.ts` re-exports entire module; tree-shaking defeated, bundle includes unused code |
| Large dependency imported fully | HIGH | `import _ from 'lodash'` instead of `import groupBy from 'lodash/groupBy'`; same for moment, icons |
| Missing dynamic imports for routes | MEDIUM | All route components statically imported; initial bundle includes all pages |
| Dev dependencies in production | HIGH | `devDependencies` imported in production code; or dev-only packages in `dependencies` |

### Detection patterns:
- `import { x } from './components'` where `./components/index.ts` re-exports 50+ components
- `import moment from 'moment'` (suggest `date-fns` or `dayjs`)
- `import * as Icons from '@heroicons/react'`
- Webpack bundle analyzer or `next build` output showing oversized chunks

---

## CSS and Styling

| Check | Severity | Description |
|-------|----------|-------------|
| Hardcoded breakpoints scattered | MEDIUM | Magic numbers like `@media (max-width: 768px)` instead of design tokens/variables |
| Desktop-first media queries | LOW | `max-width` queries instead of mobile-first `min-width`; not wrong but inconsistent |
| CSS-in-JS in hot path | MEDIUM | Runtime CSS-in-JS (styled-components, emotion) in list items or frequently re-rendered components |
| Missing responsive handling | HIGH | Layout breaks at common viewport widths; no media queries or responsive utilities present |
| Unused CSS classes | LOW | Large CSS files with classes not referenced in any component |
| Z-index arms race | LOW | Arbitrary high z-index values (999, 9999) without a z-index scale/system |

---

## Client-Side Security

| Check | Severity | Description |
|-------|----------|-------------|
| `dangerouslySetInnerHTML` / `v-html` with user content | CRITICAL | Raw HTML injection without DOMPurify or equivalent sanitization |
| Auth tokens in localStorage | HIGH | JWTs or session tokens in localStorage (XSS-accessible); should use httpOnly cookies |
| Missing CSP headers | HIGH | No Content-Security-Policy header; or `unsafe-inline`, `unsafe-eval` in policy |
| `postMessage` without origin check | CRITICAL | `window.addEventListener('message', ...)` without verifying `event.origin` |
| Sensitive data in client bundle | CRITICAL | API keys, database URLs, or secrets in client-side code (check `NEXT_PUBLIC_`, `VITE_` prefixed vars) |
| Open redirect via query params | HIGH | `router.push(searchParams.get('redirect'))` without validating destination is same-origin |

### Detection patterns:
- Search for `dangerouslySetInnerHTML`, `v-html`, `[innerHTML]`, `{@html`
- `localStorage.setItem('token',` or `localStorage.getItem('token')`
- `process.env.NEXT_PUBLIC_` containing values that look like secrets
- `window.addEventListener('message',` without `event.origin` check nearby

---

## Performance

### Core Web Vitals
| Check | Severity | Description |
|-------|----------|-------------|
| Unoptimized images | HIGH | `<img>` without width/height (CLS), without lazy loading, without next/image or equivalent |
| Web font layout shift | MEDIUM | Custom fonts without `font-display: swap` or `optional`; FOUT causing CLS |
| Synchronous third-party scripts | HIGH | `<script src="...">` without `async`/`defer` in `<head>` blocking FCP |
| Missing `loading="lazy"` on below-fold images | MEDIUM | Images below viewport loaded eagerly, hurting LCP |
| Large JS execution blocking FID | HIGH | Synchronous computation >50ms on main thread during page load |
| Layout thrashing | MEDIUM | Read-then-write DOM patterns in loops (forced synchronous layout) |

### Detection patterns:
- `<img` tags without `width`/`height` attributes and without `next/image` wrapper
- `@font-face` without `font-display` property
- `<script>` tags without `async`, `defer`, or `type="module"`
- Large `useEffect` bodies with synchronous computation

---

## Common AI Slop

These patterns indicate AI-generated code that was accepted without review:

| Pattern | Severity | What to look for |
|---------|----------|------------------|
| Duplicate components with minor variation | MEDIUM | `PrimaryButton`, `SecondaryButton`, `DangerButton` that are identical except for one prop; should be one `Button` with variant prop |
| Over-abstracted layout wrappers | LOW | `<PageWrapper>`, `<ContentContainer>`, `<MainSection>` that add nothing but a `<div>` with a class |
| Fake loading states | HIGH | `isLoading` state that is set to `true` then immediately `false`, or `setTimeout` faking a loading delay with no real async operation |
| Placeholder error handling | CRITICAL | `catch (error) { console.log(error) }` with no user feedback, no retry, no error boundary |
| Unused state variables | MEDIUM | State declared and set but never read, or read but never affects rendering |
| Hardcoded responsive breakpoints | MEDIUM | `useMediaQuery('(max-width: 768px)')` scattered through 20 components instead of a shared constant |
| Copy-pasted fetch calls | HIGH | Identical fetch-parse-setState-catch pattern in 10+ components instead of a shared hook or service |
| Form without validation | HIGH | `<form onSubmit={handleSubmit}>` where `handleSubmit` sends data directly without any field validation |
| Mock data left in production code | CRITICAL | `const users = [{ id: 1, name: "John Doe" }]` serving as actual data source |

---

## Testing Requirements

| Requirement | Priority | Details |
|-------------|----------|---------|
| Component unit tests | REQUIRED | Each non-trivial component has tests covering render, interaction, and edge states |
| Hook tests | REQUIRED | Custom hooks tested independently with `renderHook` |
| E2E for critical flows | REQUIRED | Login, signup, primary user journey, payment flow (if applicable) |
| Visual regression | RECOMMENDED | Screenshot comparison for key pages/components |
| Accessibility tests | REQUIRED | `axe-core` or equivalent in component tests; keyboard navigation in E2E |
| SSR rendering tests | RECOMMENDED | Server-rendered output matches expected HTML for SEO-critical pages |
| Error boundary coverage | REQUIRED | Error boundaries tested with components that throw |

### Minimum coverage expectations:
- Shared/reusable components: 90%+ coverage
- Page components: critical path tested via E2E
- Utility functions: 100% coverage
- Custom hooks: 100% coverage for public API
