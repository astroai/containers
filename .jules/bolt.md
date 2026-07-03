## 2024-05-24 - Ray Process Overhead
**Learning:** Checking Ray cluster state multiple times per endpoint/reconciliation loop by repeatedly calling `list_ray_nodes()` causes significant overhead due to multiple subprocess spawns calling `ray.init()`.
**Action:** When querying Ray nodes for state mapping, cache the result of `list_ray_nodes()` (a list of dictionaries) and pass it into helper functions like `live_worker_node_ips()`, `node_ip_to_id()`, and `count_live_nodes()` instead of letting each function fetch the nodes independently.
