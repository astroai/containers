## 2026-07-06 - Backend-Rendered HTML Forms UX Insight
**Learning:** In purely backend-rendered Python templates (like FastAPI generating HTML directly), adding standard Javascript `onsubmit` confirmation dialogs is a highly effective, zero-dependency way to prevent destructive actions (like stopping clusters or cleaning workers) without introducing complex frontend frameworks.
**Action:** When working on backend-rendered UI projects without a dedicated frontend framework, prioritize native browser features (like `confirm()`) and semantic HTML (like `role="alert"`) for immediate UX and accessibility wins before reaching for external libraries or custom Javascript.
## 2026-07-07 - Native Form Validation
**Learning:** For purely backend-rendered UI without external frameworks, leveraging native browser form validation (like the `required` attribute) prevents server-side 422 errors for empty submissions while improving keyboard accessibility.
**Action:** Always prefer native HTML5 validation over custom Javascript for simple constraints in backend-rendered forms.
