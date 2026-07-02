## 2024-11-20 - Add Confirmation to Destructive Actions
**Learning:** Added `onsubmit="return confirm(...);"` directly to form actions for destructive operations ("Stop cluster" and "Clean orphaned workers") to prevent accidental deletion and provide immediate user feedback.
**Action:** Always add native confirmation dialogs to buttons/forms that perform unrecoverable or destructive operations.
