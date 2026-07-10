## 2026-07-06 - Backend-Rendered HTML Forms UX Insight
**Learning:** In purely backend-rendered Python templates (like FastAPI generating HTML directly), adding standard Javascript `onsubmit` confirmation dialogs is a highly effective, zero-dependency way to prevent destructive actions (like stopping clusters or cleaning workers) without introducing complex frontend frameworks.
**Action:** When working on backend-rendered UI projects without a dedicated frontend framework, prioritize native browser features (like `confirm()`) and semantic HTML (like `role="alert"`) for immediate UX and accessibility wins before reaching for external libraries or custom Javascript.

## 2024-05-24 - Tooltips on Disabled Fieldset Elements
**Learning:** Native `<fieldset disabled>` in HTML suppresses mouse events on all its children (via pointer-events), preventing standard `title` attributes on `<button>` elements from displaying on hover.
**Action:** When a tooltip is needed on a disabled button inside a fieldset, wrap the button in a `<span>` with the `title` attribute. Then, apply `pointer-events: none` directly to the `<button>`, and `pointer-events: auto` to the wrapper `<span>` when the fieldset is disabled, so the span can capture hover events.
