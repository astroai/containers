## 2026-07-04 - Optimize Subprocess and Ray Client Calls
**Learning:** `list_ray_nodes()` launches a python subprocess that runs `ray.init()`, taking significant time. Redundantly querying Ray nodes across `count_live_nodes`, `live_worker_node_ips`, and `node_ip_to_id` adds up rapidly, particularly during frequent reconcile loops.
**Action:** Always fetch stateful information (like ray nodes) once and pass the result down to helper functions rather than allowing helpers to implicitly fetch their own dependencies.

## 2024-05-18 - Optimize double fetching nodes
**Learning:** `wait_for_node_count()` queried nodes twice before waiting, and then threw away the data. In the same scope callers typically needed to immediately reconcile, which fetched again.
**Action:** Always return fetched nodes from wait functions and pass them into subsequent calls (like `reconcile_cluster`) that take `nodes` as an optional argument.
