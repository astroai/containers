## 2024-05-18 - Added confirmation dialogs for destructive actions
**Learning:** Native `onsubmit="return confirm('...');"` is a very fast and effective way to add a safety net for destructive actions (like "Stop cluster") in backend-rendered forms (like FastAPI + pure HTML) without needing complex frontend frameworks or state management.
**Action:** When working on backend-rendered UI forms for destructive operations, always check if a native confirmation dialog exists. If not, add one using `onsubmit`.
