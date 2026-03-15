# UI/UX and Accessibility Review Checklist

This document provides the complete UX and accessibility checklist for UCR review agents evaluating web applications and websites. Every check includes what to look for, how to verify it from source code, the severity when violated, and common AI-generated mistakes.

---

# Part 1: UX Review

## 1. Mobile-First Design

### 1.1 Viewport Meta Tag

**What to check**: The HTML document includes a correct viewport meta tag.

**How to verify from code**:
- Search for `<meta name="viewport"` in HTML templates, `index.html`, or layout files
- Correct value: `content="width=device-width, initial-scale=1"`
- Flag if `maximum-scale=1` or `user-scalable=no` is present (prevents zoom, accessibility violation)

**Severity**: Major if viewport meta is missing (entire layout breaks on mobile). Moderate if zoom is disabled.

**Common AI mistakes**: Missing the viewport tag entirely. Adding `user-scalable=no` because a tutorial said to. Copying a viewport tag with `maximum-scale=1`.

### 1.2 Responsive Breakpoints

**What to check**: CSS/styles handle standard breakpoints without breaking layout.

**How to verify from code**:
- Search for `@media` queries in CSS/SCSS files
- Check breakpoints cover: 320px (small phone), 375px (standard phone), 768px (tablet), 1024px (small laptop), 1440px (desktop)
- Verify breakpoints use `min-width` (mobile-first) or `max-width` (desktop-first) consistently, not a mix
- Check for hardcoded widths in inline styles that override responsive behavior

**Severity**: Major if primary flow is broken at any standard breakpoint. Moderate for minor layout issues.

### 1.3 No Horizontal Scroll

**What to check**: No element overflows the viewport horizontally.

**How to verify from code**:
- Search for `width` values exceeding `100vw` or hardcoded pixel widths (e.g., `width: 1200px`)
- Search for `overflow-x: hidden` on `body` or `html` (this hides the symptom, not the cause)
- Check for `position: absolute` or `position: fixed` with `left` + `width` exceeding viewport
- Check tables and code blocks: need `overflow-x: auto` on their container

**Severity**: Moderate. Horizontal scroll on mobile is a significant UX problem.

**Common AI mistakes**: Setting fixed widths on containers. Using `overflow-x: hidden` on body to hide the problem instead of fixing the element that overflows.

---

## 2. Touch Targets

### 2.1 Minimum Size

**What to check**: All interactive elements (buttons, links, inputs, checkboxes) are at least 44x44px on touch devices.

**How to verify from code**:
- Check button/link styles for `min-height` and `min-width` (or `padding` that achieves 44px)
- Check icon buttons specifically (small icon with no padding is common)
- Check checkbox and radio custom styling
- Check inline links in dense text (may need extra padding on mobile)

**Severity**: Moderate. Small touch targets cause frustration and are an accessibility issue (WCAG 2.5.8 Target Size).

### 2.2 Adequate Spacing

**What to check**: Interactive elements have sufficient space between them to prevent accidental taps.

**How to verify from code**:
- Check `gap`, `margin`, and `padding` between clickable elements in lists, toolbars, and navigation
- Minimum 8px between adjacent touch targets
- Check for tightly packed link lists on mobile

**Severity**: Minor for most cases. Moderate if misstaps could cause destructive actions (delete buttons close to other buttons).

---

## 3. Responsive Layouts

### 3.1 Flexbox/Grid Usage

**What to check**: Layouts use CSS flexbox or grid for responsive behavior, not absolute positioning or floats for page structure.

**How to verify from code**:
- Check main layout components for `display: flex` or `display: grid`
- Flag `float` used for page layout (acceptable for text wrapping only)
- Flag `position: absolute` used for layout instead of layering/overlays
- Check that grid/flex containers use `fr`, `%`, `auto`, `min-content`, `max-content` -- not all fixed pixel values

**Severity**: Minor if layout works but uses outdated techniques. Moderate if layout breaks on resize.

### 3.2 No Fixed Widths

**What to check**: Content containers use relative units, not fixed pixel widths.

**How to verify from code**:
- Search for `width:` with pixel values on containers, cards, modals, forms
- Acceptable: `max-width: 1200px` with `width: 100%` (constrains maximum, still responsive)
- Unacceptable: `width: 800px` on a form container (overflows on mobile)
- Check images: should have `max-width: 100%` and `height: auto`

**Severity**: Moderate if fixed widths cause overflow on common screen sizes. Minor if only affects very narrow screens.

### 3.3 Fluid Typography

**What to check**: Font sizes scale reasonably across screen sizes.

**How to verify from code**:
- Check for `clamp()` or `calc()` based font sizing (preferred for fluid typography)
- Check for media queries that adjust font sizes at breakpoints (acceptable alternative)
- Flag very small font sizes: anything below `14px` / `0.875rem` for body text
- Check heading sizes on mobile: should be reduced from desktop sizes

**Severity**: Minor for most cases. Moderate if text is unreadable on mobile (too small or too large).

---

## 4. Interaction Patterns

### 4.1 Clear CTAs (Calls to Action)

**What to check**: Primary actions are visually prominent. Secondary actions are visually distinct from primary. Destructive actions require confirmation.

**How to verify from code**:
- Check for button variants: primary, secondary, destructive/danger styling
- Verify destructive actions (delete, remove, cancel subscription) have a confirmation step
- Check that primary CTA text is action-oriented ("Save changes", "Create account") not vague ("Submit", "OK")

**Severity**: Minor for unclear CTA text. Moderate for destructive actions without confirmation. Major if the primary flow CTA is not findable.

### 4.2 Interactive States

**What to check**: Interactive elements have visible hover, focus, active, and disabled states.

**How to verify from code**:
- Check CSS for `:hover`, `:focus`, `:active`, `:disabled` pseudo-class styling on buttons, links, and form elements
- Check that `:focus` style is distinct and visible (not just `outline: none` with no replacement)
- Check disabled state: visually different (opacity, color), `pointer-events: none` or equivalent, `aria-disabled` or `disabled` attribute

**Severity**: Moderate if focus states are removed (accessibility issue). Minor if hover/active states are missing.

**Common AI mistakes**: `outline: none` on `:focus` to "clean up" the UI, destroying keyboard navigation visibility. Disabled buttons with no visual distinction. Hover styles that also apply on touch devices (stuck hover state).

### 4.3 Loading States

**What to check**: Long-running operations show a loading indicator. Buttons are disabled during submission to prevent double-submit.

**How to verify from code**:
- Check form submission handlers: button should be disabled while async operation is in progress
- Check for loading state variables: `isLoading`, `isPending`, `loading`, `submitting`
- Check that loading state is shown to the user (spinner, skeleton, progress bar)
- Check that loading state is set in both the start and end (including error) paths

**Severity**: Moderate for missing loading states on primary flows (users don't know if their action worked). Minor on secondary flows. Major if double-submit causes data duplication.

**Common AI mistakes**: Setting `isLoading = true` but never setting it back to `false` on error. Loading spinner with no timeout (infinite spinner if the request hangs). Button disabled during load but no visual loading indicator.

---

## 5. Error States

### 5.1 Inline Validation

**What to check**: Form validation errors appear next to the relevant field, not just in a generic error banner.

**How to verify from code**:
- Check form validation: errors should be associated with specific fields
- Error messages should appear below or adjacent to the field
- Error fields should have visual distinction (red border, error icon)
- Check that validation runs on blur (not just on submit) for long forms

**Severity**: Moderate for forms with many fields (users can't find what's wrong). Minor for simple forms.

### 5.2 Clear Error Messages

**What to check**: Error messages are user-friendly, specific, and actionable.

**How to verify from code**:
- Check error message strings: should say what's wrong AND what to do ("Password must be at least 8 characters" not "Invalid input")
- Check for technical error messages shown to users: HTTP status codes, exception names, stack traces
- Check for generic messages: "Something went wrong" with no recovery guidance

**Severity**: Moderate if errors in primary flows are unhelpful. Minor for secondary flows.

### 5.3 Preserved User Input

**What to check**: When a form submission fails, the user's input is preserved -- they don't have to re-enter everything.

**How to verify from code**:
- Check that form state is maintained on validation failure (not cleared)
- For server-side rendered forms: check that the server re-renders with the submitted values
- For SPAs: check that form state is not reset on error response
- Check file uploads: these cannot be preserved, but the user should be told which files they need to re-select

**Severity**: Moderate for long forms. Minor for short forms.

**Common AI mistakes**: `form.reset()` called in the catch block. React state cleared on re-render. Full page redirect on error that loses all form state.

---

## 6. Empty States

### 6.1 Meaningful Empty State Messages

**What to check**: When a list, table, or content area is empty, the user sees a helpful message instead of a blank area.

**How to verify from code**:
- Check list/table components for empty state handling: `if (items.length === 0)` or equivalent
- Message should explain why it's empty ("No results match your filter" vs "No items") and suggest next steps
- Check for empty divs rendered when data is null/undefined/empty array

**Severity**: Minor for most cases. Moderate for primary features where an empty state is the first experience (new user onboarding).

---

## 7. Navigation

### 7.1 Consistent Navigation

**What to check**: Navigation structure is consistent across pages. Users always know where they are.

**How to verify from code**:
- Check that navigation component is shared (not duplicated per page)
- Check for active state on current navigation item
- Verify navigation doesn't change structure between pages (items appearing/disappearing)

**Severity**: Minor. Moderate if navigation inconsistency causes users to lose their place.

### 7.2 Back Button Behavior

**What to check**: The browser back button works as expected. Single-page applications manage history correctly.

**How to verify from code**:
- For SPAs: check that route changes push to history (`history.pushState`, `router.push`)
- Check that modals, tabs, and filters don't push history entries (unless they represent a meaningful state)
- Check that `history.replaceState` is used for state that shouldn't be in back-button history (sort order, pagination within a view)

**Severity**: Moderate if back button breaks navigation or causes data loss. Minor if it just navigates to an unexpected page.

---

## 8. Typography

### 8.1 Readable Sizes

**What to check**: Body text is at least 16px. Line height is at least 1.5 for body text.

**How to verify from code**:
- Check base font size: `html { font-size: 16px }` or `body { font-size: 1rem }` minimum
- Check line height: `line-height: 1.5` minimum for body text, `1.2` for headings
- Check paragraph max-width: 60-80 characters per line (approximately `max-width: 65ch`)

**Severity**: Moderate if text is too small to read comfortably on mobile. Minor for desktop.

---

## 9. Forms

### 9.1 Logical Tab Order

**What to check**: Tab moves through form fields in a logical order (top to bottom, left to right in LTR layouts).

**How to verify from code**:
- Check for `tabindex` values: `tabindex="0"` is fine, positive values (1, 2, 3) override natural order and are almost always wrong
- Check that the DOM order matches the visual order (CSS layout can reorder visually without changing tab order)
- Check for `tabindex="-1"` on elements that should be focusable

**Severity**: Moderate. Broken tab order is a major accessibility and usability issue.

### 9.2 Autocomplete Attributes

**What to check**: Form fields have appropriate `autocomplete` attributes to help browsers and password managers.

**How to verify from code**:
- Login form: `autocomplete="username"` on email/username, `autocomplete="current-password"` on password
- Registration form: `autocomplete="new-password"` on password field
- Address forms: `autocomplete="street-address"`, `autocomplete="postal-code"`, etc.
- Search fields: `autocomplete="off"` if autocomplete is inappropriate

**Severity**: Minor for most fields. Moderate for login/password fields (breaks password managers).

### 9.3 Appropriate Input Types

**What to check**: Form inputs use the correct `type` attribute for their content.

**How to verify from code**:
- Email: `type="email"` (enables email keyboard on mobile, browser validation)
- Phone: `type="tel"` (enables numeric keyboard on mobile)
- URL: `type="url"`
- Number: `type="number"` with `min`, `max`, `step` where appropriate
- Date: `type="date"` or a date picker component
- Password: `type="password"` (with show/hide toggle)

**Severity**: Minor. Incorrect types degrade mobile experience but don't break functionality.

**Common AI mistakes**: Using `type="text"` for everything. Using `type="number"` for phone numbers (wrong -- phone numbers can start with + and have hyphens).

---

## 10. User Flow Friction

### 10.1 Step Count Analysis

**What to check**: Primary user flows are as short as possible. Each step serves a clear purpose.

**How to verify from code**:
- Trace primary flows (signup, checkout, main feature) through the route/component tree
- Count the number of pages/screens/steps
- Identify steps that could be combined or eliminated
- Check for unnecessary confirmation pages, intermediate screens, or redundant data entry

**Severity**: Minor for individual friction points. Moderate if the cumulative friction significantly impacts the primary flow.

---

# Part 2: Accessibility Review (WCAG 2.2 AA)

## 1. Keyboard Access

### 1.1 All Interactive Elements Reachable

**What to check**: Every interactive element (button, link, input, select, checkbox, custom control) is reachable via Tab key.

**How to verify from code**:
- Check that interactive elements use semantic HTML: `<button>`, `<a href>`, `<input>`, `<select>` -- these are keyboard-accessible by default
- If custom elements are used (`<div onClick>`), check for `tabIndex="0"`, `role`, and keyboard event handlers
- Check for `tabIndex="-1"` on elements that should be keyboard-accessible (this removes them from tab order)
- Search for `onClick` on `<div>`, `<span>`, `<li>` without `role="button"` and `tabIndex="0"` and `onKeyDown`

**Severity**: Major. Keyboard-inaccessible interactive elements make the application unusable for keyboard users and many assistive technology users.

**Common AI mistakes**: Using `<div onClick>` instead of `<button>`. Forgetting keyboard handlers when creating custom components. Applying `tabIndex="-1"` thinking it means "this element can be focused."

### 1.2 Enter/Space Activate

**What to check**: Interactive elements activated by Enter and/or Space keys (buttons: both; links: Enter; checkboxes: Space).

**How to verify from code**:
- Semantic HTML handles this automatically
- For custom elements: check for `onKeyDown` or `onKeyPress` handler that responds to Enter (keyCode 13) and Space (keyCode 32)
- Check that Space doesn't scroll the page when a custom button is focused (need `event.preventDefault()`)

**Severity**: Major if primary action buttons don't respond to keyboard. Moderate for secondary elements.

### 1.3 Escape Closes

**What to check**: Modals, dropdowns, popovers, and overlays close when Escape is pressed.

**How to verify from code**:
- Find modal/dialog/dropdown/popover components
- Check for Escape key handler: `event.key === 'Escape'` or `event.keyCode === 27`
- Check that the handler restores focus to the element that triggered the modal

**Severity**: Moderate. Keyboard users trapped in a modal with no Escape support cannot continue using the application.

---

## 2. Focus Management

### 2.1 Visible Focus Indicators

**What to check**: All focusable elements have a visible focus indicator.

**How to verify from code**:
- Search for `outline: none`, `outline: 0`, `:focus { outline: none }` -- if present, verify a replacement focus style exists
- Check for `:focus-visible` (preferred: shows focus ring only for keyboard users)
- Focus indicator must have at least 3:1 contrast against the background
- Check that the focus indicator is not obscured by adjacent elements or overflow: hidden

**Severity**: Major. WCAG 2.4.7 (Focus Visible) is a Level AA requirement. Missing focus indicators make keyboard navigation impossible.

**Common AI mistakes**: Global `* { outline: none }` in CSS reset. `:focus { outline: none }` without a replacement style. Focus indicator color that matches the background. Focus indicator hidden by `overflow: hidden` on the parent.

### 2.2 Logical Focus Order

**What to check**: Focus order follows the visual layout. Focus doesn't jump around the page unexpectedly.

**How to verify from code**:
- Check DOM order matches visual order (CSS `order`, `flex-direction: row-reverse`, `grid-area` can cause mismatches)
- Check for positive `tabIndex` values (1, 2, 3) that override natural order
- Check that dynamically rendered content (e.g., React portals) doesn't appear in an unexpected position in the focus order

**Severity**: Moderate. Confusing focus order makes navigation unpredictable.

### 2.3 Focus Trapped in Modals

**What to check**: When a modal is open, Tab cycles through modal content only, not the background content.

**How to verify from code**:
- Find modal/dialog components
- Check for focus trap implementation: libraries like `focus-trap`, `focus-trap-react`, or custom implementation
- The first and last focusable elements in the modal should wrap Tab focus
- Background content should have `aria-hidden="true"` or `inert` attribute when modal is open

**Severity**: Major. Without focus trapping, keyboard users tab into invisible background content behind the modal.

### 2.4 Focus Restored on Close

**What to check**: When a modal, dropdown, or popover closes, focus returns to the trigger element.

**How to verify from code**:
- Check the close handler: should restore focus to the element that opened the modal
- Common pattern: save `document.activeElement` before opening, restore on close
- Check that `autoFocus` on the first element inside the modal moves focus into the modal on open

**Severity**: Moderate. Without focus restoration, keyboard users lose their position on the page.

---

## 3. Semantic HTML

### 3.1 Heading Hierarchy

**What to check**: Headings follow a logical hierarchy: h1 > h2 > h3. No skipped levels (h1 followed by h3). One h1 per page.

**How to verify from code**:
- Search for `<h1>`, `<h2>`, `<h3>`, `<h4>`, `<h5>`, `<h6>` in templates/components
- Check that headings are not used for styling (use CSS instead of choosing h3 because it "looks right")
- Check that heading level matches content hierarchy, not visual size
- Verify one `<h1>` per page (in SPAs, per view)

**Severity**: Moderate. Screen reader users navigate by heading structure. Broken hierarchy makes navigation confusing.

**Common AI mistakes**: Using heading tags for visual styling. Skipping heading levels. Multiple h1 elements on a page. Using `<div className="heading">` instead of actual heading elements.

### 3.2 Landmark Regions

**What to check**: Page uses HTML5 landmark elements: `<header>`, `<nav>`, `<main>`, `<aside>`, `<footer>`.

**How to verify from code**:
- Check that the page has at least `<main>` wrapping the primary content
- Check for `<nav>` on navigation areas
- If there are multiple navs, they should have `aria-label` to distinguish them
- Check that landmark regions don't nest incorrectly (`<main>` inside `<main>`)

**Severity**: Moderate. Landmarks enable screen reader users to skip directly to sections of the page.

### 3.3 Correct Element Usage

**What to check**: Lists use `<ul>`/`<ol>`/`<li>`. Tables use `<table>` with `<th>` for headers. Buttons use `<button>`. Links use `<a href>`.

**How to verify from code**:
- Search for `<div>` or `<span>` with `onClick` handlers -- should usually be `<button>`
- Check navigation menus: should use `<nav>` with `<ul>` and `<li>`, not `<div>` soup
- Check data displays: tabular data should use `<table>`, not CSS grid mimicking a table
- Check that `<a>` is used for navigation (changes URL) and `<button>` for actions (triggers behavior)

**Severity**: Moderate. Incorrect elements break screen reader announcements, keyboard navigation, and browser features.

**Common AI mistakes**: `<div onClick>` everywhere instead of `<button>`. `<a>` without `href` (not keyboard accessible, not announced as a link). `<span>` styled as a link. `<div role="button">` when `<button>` would work.

---

## 4. ARIA

### 4.1 ARIA Used Correctly

**What to check**: ARIA attributes are used to supplement semantic HTML, not to replace it. ARIA is correct and necessary.

**How to verify from code**:
- First rule of ARIA: don't use ARIA if a native HTML element will do the job
- Check for incorrect ARIA: `role="button"` on a `<div>` (should be `<button>`), `aria-label` on a `<div>` that's not interactive
- Check that `role` values are valid (not made-up roles)
- Check that required states are present: `role="checkbox"` requires `aria-checked`, `role="tab"` requires `aria-selected`
- Check that `aria-label` and `aria-labelledby` reference actual content

**Severity**: Major if ARIA is incorrect and conveys wrong information (worse than no ARIA). Moderate if ARIA is missing where needed.

**Common AI mistakes**: Using `aria-label` on everything instead of using visible labels. Using `role="button"` on a `<div>` instead of using `<button>`. Adding `aria-hidden="true"` to content that should be visible to screen readers. Using `aria-live="assertive"` on non-urgent updates (interrupts the user).

### 4.2 Live Regions

**What to check**: Dynamic content updates (toast notifications, form submission results, live data) use `aria-live` to announce changes to screen readers.

**How to verify from code**:
- Search for `aria-live` attributes
- Check that toast/notification components use `role="alert"` (urgent) or `role="status"` (non-urgent)
- Check that the live region exists in the DOM before content is injected (content injected into a newly created live region may not be announced)
- Check polite vs assertive: `aria-live="polite"` for non-urgent updates, `aria-live="assertive"` for errors and urgent notifications

**Severity**: Moderate. Screen reader users won't know about dynamic updates without live regions.

---

## 5. Color and Contrast

### 5.1 Text Contrast

**What to check**: Normal text has at least 4.5:1 contrast ratio. Large text (18px+ or 14px+ bold) has at least 3:1.

**How to verify from code**:
- Check text color against background color in CSS
- Pay attention to: light gray text on white backgrounds, white text on light-colored buttons, placeholder text
- Check that text on images/gradients has sufficient contrast (may need a text shadow or background overlay)
- Check dark mode if implemented: contrast ratios must be met in both themes

**Severity**: Major for body text below 4.5:1 (WCAG 1.4.3 Level AA). Moderate for large text below 3:1.

### 5.2 UI Component Contrast

**What to check**: UI components (borders, icons, form field outlines) have at least 3:1 contrast against their background.

**How to verify from code**:
- Check form field borders: light gray borders on white background often fail
- Check icon-only buttons: icon color must contrast with background
- Check custom checkboxes/radios: the checked/unchecked state must be distinguishable with 3:1 contrast

**Severity**: Moderate. WCAG 1.4.11 (Non-text Contrast) Level AA.

### 5.3 No Information by Color Alone

**What to check**: Color is not the only way to convey information (error states, required fields, status indicators).

**How to verify from code**:
- Error states: must have text or icon in addition to red color
- Required fields: must have text ("Required") or symbol (*) with legend, not just red label
- Status indicators (success/warning/error): must have icon or text in addition to color
- Charts/graphs: must use patterns or labels in addition to color

**Severity**: Moderate. WCAG 1.4.1 (Use of Color) Level A.

---

## 6. Motion

### 6.1 Reduced Motion

**What to check**: Animations and transitions respect `prefers-reduced-motion` media query.

**How to verify from code**:
- Search for `@media (prefers-reduced-motion: reduce)` in CSS
- Check that CSS animations/transitions have reduced-motion alternatives:
  ```css
  @media (prefers-reduced-motion: reduce) {
    * { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; }
  }
  ```
- Check JavaScript animations (GSAP, Framer Motion, etc.) for motion preference detection
- Verify no auto-playing videos or GIFs without pause controls

**Severity**: Moderate. WCAG 2.3.3 (Animation from Interactions) Level AAA, but widely expected for AA compliance. Essential for users with vestibular disorders.

**Common AI mistakes**: No reduced-motion support at all. Fancy page transitions and scroll animations with no opt-out. Auto-playing carousel with no pause button.

---

## 7. Form Labels

### 7.1 Every Input Has a Visible Label

**What to check**: Every form input has a visible `<label>` associated with it. Placeholder text is NOT a substitute for a label.

**How to verify from code**:
- For each `<input>`, `<select>`, `<textarea>`: verify a `<label for="inputId">` exists, or the input is wrapped in a `<label>`
- Check that the `for` attribute matches the input's `id`
- Check that placeholder text is supplementary, not the only label
- For icon-only inputs: must have `aria-label` or `aria-labelledby`

**Severity**: Major. Missing labels make forms unusable for screen readers. WCAG 1.3.1 (Info and Relationships) Level A.

**Common AI mistakes**: Using `placeholder` instead of `<label>`. Label exists in the DOM but is visually hidden AND not associated with the input. `aria-label` used when a visible label is available and appropriate.

### 7.2 Fieldset/Legend for Groups

**What to check**: Groups of related inputs (radio buttons, checkboxes, address fields) are wrapped in `<fieldset>` with a `<legend>`.

**How to verify from code**:
- Find groups of radio buttons or checkboxes with the same `name`: should be wrapped in `<fieldset>`
- `<legend>` should describe the group ("Shipping method", "Notification preferences")
- Address field groups should be in a fieldset
- For custom components: check for `role="group"` with `aria-labelledby` as an alternative

**Severity**: Moderate. Without fieldset/legend, screen readers announce each radio button without context.

### 7.3 Error Messages Linked to Inputs

**What to check**: Validation error messages are programmatically associated with their input field using `aria-describedby`.

**How to verify from code**:
- Check error message display: `<span id="email-error">Email is required</span>`
- Check input: `<input aria-describedby="email-error" aria-invalid="true">`
- Check that `aria-invalid="true"` is set on invalid fields
- Check that `aria-describedby` is only present when the error is visible

**Severity**: Moderate. Without association, screen reader users see the field as invalid but don't hear the error message.

---

## 8. Images

### 8.1 Meaningful Alt Text

**What to check**: Images that convey information have descriptive alt text. Decorative images have `alt=""`.

**How to verify from code**:
- Check all `<img>` tags for `alt` attribute
- Meaningful images: `alt` should describe the content or function, not the filename ("Photo of team at conference" not "IMG_2847.jpg")
- Icons that serve as buttons: alt should describe the action ("Close", "Search", "Menu")
- Decorative images: `alt=""` (empty, not absent -- absent alt is an error)
- Complex images (charts, diagrams): need `alt` plus a longer description (via `aria-describedby` or adjacent text)

**Severity**: Major if informational images have no alt text. Minor if alt text is present but could be improved.

**Common AI mistakes**: Missing `alt` attribute entirely. `alt="image"` or `alt="icon"` (useless). Decorative images with non-empty alt (clutters screen reader experience). Very long alt text that should be in a caption or adjacent text.

---

## 9. Status Messaging

### 9.1 Dynamic Status Updates

**What to check**: Status changes (success messages, error alerts, progress updates) are announced to screen readers.

**How to verify from code**:
- Toast/snackbar components: should use `role="status"` (polite) or `role="alert"` (assertive)
- Form submission success/failure: should use `aria-live` region
- Loading indicators: should have `aria-busy="true"` on the region being loaded, or announce loading state
- Search results count: should be announced when results update

**Severity**: Moderate. Screen reader users miss status updates without proper announcements.

---

## 10. Modal/Dialog

### 10.1 Dialog Implementation

**What to check**: Modals use proper dialog semantics and behavior.

**How to verify from code**:
- Check for `role="dialog"` or `<dialog>` element
- Check for `aria-modal="true"` (or native `<dialog>` with `.showModal()`)
- Check for `aria-labelledby` pointing to the modal title
- Check focus management:
  1. Focus moves into the modal on open (first focusable element or the dialog itself)
  2. Focus is trapped within the modal (Tab cycles through modal content)
  3. Escape closes the modal
  4. Focus returns to the trigger element on close
- Check that background content has `aria-hidden="true"` or `inert` while modal is open

**Severity**: Major if modal has no keyboard/screen reader support. Moderate for missing individual features (e.g., Escape to close works but focus isn't trapped).

**Common AI mistakes**: Using a styled `<div>` as a modal with no dialog semantics. Focus trap not implemented. Focus not restored on close. `aria-modal` without `aria-hidden` on background. Using the native `<dialog>` without `.showModal()` (doesn't get modal behavior).

---

## 11. Screen Reader

### 11.1 Content Order

**What to check**: The DOM order matches the visual order. Content that appears first visually should appear first in the DOM.

**How to verify from code**:
- Check for CSS `order` property on flex/grid items
- Check for `flex-direction: row-reverse` or `column-reverse`
- Check for absolute/fixed positioning that visually reorders content
- Check for CSS Grid `grid-row` and `grid-column` that reorder content

**Severity**: Moderate. Screen readers read in DOM order, not visual order.

### 11.2 Hidden Content

**What to check**: Content hidden from sighted users is also hidden from screen readers, and vice versa.

**How to verify from code**:
- `display: none` and `visibility: hidden` hide from both (correct for hidden content)
- `aria-hidden="true"` hides from screen readers only (correct for decorative elements)
- Visually-hidden class (screen reader only text) uses proper technique:
  ```css
  .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0,0,0,0); border: 0; }
  ```
- Check that `aria-hidden="true"` is not used on focusable elements (creates a confusing experience)
- Check for off-screen content (e.g., `left: -9999px`) that may be read by screen readers

**Severity**: Moderate if screen reader users hear content that makes no sense in context. Major if `aria-hidden` is on focusable interactive content.

### 11.3 Skip Navigation Link

**What to check**: A "Skip to main content" link is the first focusable element on the page.

**How to verify from code**:
- Check for a skip link at the top of the page body: `<a href="#main-content" class="sr-only focusable">Skip to main content</a>`
- Check that the target (`id="main-content"`) exists on the `<main>` element or first heading
- The skip link should become visible on focus (for sighted keyboard users)

**Severity**: Moderate. Skip links allow keyboard users to bypass repetitive navigation on every page.

**Common AI mistakes**: Skip link exists but is permanently hidden (never visible, even on focus). Skip link target ID doesn't exist. Skip link is not the first focusable element.
