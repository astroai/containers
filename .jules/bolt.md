## 2025-02-18 - Batch Ray cluster state polling
**Learning:** A codebase-specific performance pattern to avoid is redundantly calling `ray.init()` or spawning subprocesses for Ray interactions when parsing cluster state. These operations are expensive and should be batched or cached when possible.
**Action:** Pass `nodes` structure (from `list_ray_nodes()`) through function arguments in critical paths (like `reconcile_cluster` and API handlers) to avoid repeated expensive subprocess calls.
