# CANFAR Ray Manager and Worker Containers — Build Plan

## 1. Objective

Build a user-level Ray cluster prototype that works with the **current CANFAR Science Platform** without requiring KubeRay or changes to the platform control plane.

The system will consist of:

1. A **contributed CANFAR session** running a web-based Ray Manager and the Ray head process.
2. One or more **CANFAR headless sessions** running Ray workers.
3. The Ray Manager using the existing `canfar` Python client to create, monitor, and destroy worker sessions.
4. All nodes reading and writing astronomy data through the CANFAR-mounted `/arc` filesystem.
5. Local temporary data, Ray spill data, and caches using `/scratch`.

This is a controlled prototype intended initially for small clusters, typically:

- one manager session;
- one to four worker sessions;
- CPU workers, with optional GPU worker images;
- interactive astronomy processing and small distributed ML experiments.

It is not intended to replace a future KubeRay-based production service.

---

## 2. Current CANFAR Constraints

The implementation must work within these platform behaviors:

- A contributed application must expose an HTTP interface on **port 5000**.
- A contributed application must provide `/skaha/startup.sh`.
- Contributed and headless sessions have access to:
  - `/arc/home/<user>/`;
  - `/arc/projects/<project>/`;
  - `/scratch/`, which is ephemeral.
- A contributed session receives a Kubernetes Service for port 5000 only.
- Ray workers therefore cannot use a stable CANFAR-created Service for Ray control-plane traffic.
- The manager must advertise its **pod IP** to workers.
- Headless sessions can be launched with explicit CPU, RAM, GPU, command, arguments, environment variables, and replicas.
- Worker sessions are admitted independently; there is no atomic admission of the whole Ray cluster.
- The public session API does not expose arbitrary Kubernetes volume configuration or `/dev/shm` sizing.
- CANFAR sessions do not receive Kubernetes service-account credentials.
- Browser authentication to the contributed application must not be assumed to provide API credentials for creating headless sessions.

The implementation must fail clearly when direct pod-to-pod networking is unavailable.

---

## 3. Scope

### 3.1 In scope

- Build and publish the manager and worker container images.
- Start a Ray head inside a contributed session.
- Authenticate the manager to the CANFAR session API.
- Launch and destroy Ray workers as CANFAR headless sessions.
- Pass the Ray head address and cluster configuration to workers.
- Detect when workers have joined Ray.
- Run distributed Python tasks.
- Support `/arc` data access and `/scratch` temporary storage.
- Persist manager state under the user's CANFAR home directory.
- Recover or clean up worker sessions after manager restart.
- Provide cluster lifecycle controls through a web UI.
- Support separate CPU and GPU worker images.
- Provide tests, documentation, and a sample astronomy workload.

### 3.2 Out of scope for the first version

- Native KubeRay CRDs.
- Kubernetes API access from user containers.
- Production-grade autoscaling.
- Gang scheduling.
- Multi-user shared Ray clusters.
- Persistent Ray clusters surviving manager deletion.
- Ray Serve as a public inference service.
- Exposing arbitrary Ray ports through the public CANFAR ingress.
- Large-scale clusters beyond the user's CANFAR session quota.
- MPI or tightly coupled HPC workloads.
- Long-term credential storage outside the existing CANFAR client mechanisms.

---

## 4. Required Container Images

Build all images with the **same pinned Python and Ray versions**.

### 4.1 Common base image

Suggested name:

```text
images.canfar.net/<project>/canfar-ray-base:<version>
```

Responsibilities:

- Provide a pinned Python version.
- Install the pinned `ray` version.
- Install common astronomy dependencies required by the validation workload:
  - `numpy`;
  - `astropy`;
  - `pandas`;
  - `pyarrow`;
  - `fsspec`;
  - optional FITS/image-processing libraries agreed with the project owner.
- Include common health-check and diagnostic scripts.
- Run correctly as the UID/GID injected by CANFAR.
- Avoid assumptions that the container runs as root.
- Do not embed CANFAR credentials.
- Write mutable state only to `/arc`, `/scratch`, `/tmp`, or the runtime user's writable home.

The base image should not start Ray automatically.

### 4.2 Ray Manager contributed-application image

Suggested name:

```text
images.canfar.net/<project>/canfar-ray-manager:<version>
```

Derived from the common base image.

Must contain:

- the `canfar` Python package;
- the manager backend;
- the manager web frontend;
- `/skaha/startup.sh`;
- a Ray head startup wrapper;
- session monitoring and cleanup logic;
- an authentication-status page;
- a network preflight tool;
- cluster-state persistence;
- application logs suitable for `canfar logs`.

The web application must listen on:

```text
0.0.0.0:5000
```

The Ray head must not use port 5000.

Recommended Ray head behavior:

- `--head`;
- `--num-cpus=0`, so the manager remains responsive;
- fixed, documented control-plane ports;
- a bounded worker-port range;
- local object spilling under `/scratch`;
- explicit `--node-ip-address`;
- no public Ray Client or dashboard exposure;
- no authentication assumptions based on the contributed-session browser cookie.

### 4.3 Worker image (CPU and GPU)

Name:

```text
images.canfar.net/<project>/ray-worker:<version>
```

Built on `astroai/base` + `ray-base` — **no separate CUDA image**. GPU workers use CANFAR `gpu=N` at session launch; the entrypoint verifies `nvidia-smi` when `RAY_WORKER_GPUS>0`. ML/CUDA stacks belong in user pixi/uv projects (same as notebook/webterm).

Responsibilities:

- join the manager's Ray head using environment variables (`RAY_HEAD_IP`, `RAY_HEAD_PORT`, `RAY_WORKER_GPUS`);
- use the CPU/GPU counts passed by the manager;
- use `/scratch/ray/<cluster-id>/` for Ray temporary and spill data;
- remain alive using `ray start --block`;
- check the manager heartbeat periodically;
- exit if the heartbeat is stale beyond a configured threshold;
- emit useful startup and failure diagnostics;
- verify that the worker Ray version matches the manager version;
- fail clearly when GPUs are requested but not visible;
- shut down cleanly on `SIGTERM`.

### 4.4 GPU validation (Milestone E)

No separate GPU worker image. Validate on CANFAR production with `make test-canfar-ray-gpu TAG=<version>` (1 worker, `gpus=1`, Ray reports GPU resources).

---

## 5. Repository Layout

Use one repository unless the project owner requests separate repositories.

```text
canfar-ray/
├── README.md
├── pyproject.toml
├── Dockerfile.base
├── Dockerfile.manager
├── Dockerfile.worker-cpu
├── Dockerfile.worker-gpu
├── manager/
│   ├── app/
│   ├── api/
│   ├── templates/
│   ├── static/
│   └── state/
├── worker/
│   ├── start-worker.sh
│   ├── heartbeat-watch.sh
│   └── diagnostics.sh
├── scripts/
│   ├── startup-manager.sh
│   ├── network-preflight.py
│   ├── ray-health.py
│   └── cleanup-orphans.py
├── examples/
│   ├── distributed_smoke_test.py
│   ├── fits_header_scan.py
│   └── ray_train_smoke_test.py
├── tests/
│   ├── unit/
│   ├── integration/
│   └── container/
└── docs/
    ├── user-guide.md
    ├── operator-runbook.md
    ├── security.md
    └── troubleshooting.md
```

---

## 6. Manager Functional Requirements

### 6.1 Manager startup

`/skaha/startup.sh` must:

1. Validate that **`/arc/home/<user>`** (or `$HOME` when already under `/arc/home`) and **`/scratch`** are writable where expected.
2. Determine the current pod IP.
3. Create a per-session Ray temporary directory under `/scratch`.
4. Start the Ray head with fixed ports.
5. Start the manager web application on port 5000.
6. Write the manager pod IP, Ray address, Ray version, and startup timestamp into local manager state.
7. Record failures to stdout/stderr before exiting.

The manager must not advertise:

- `127.0.0.1`;
- a public ingress hostname;
- the contributed application's port-5000 Service as the Ray head address.

### 6.2 Suggested Ray port allocation

Use a fixed, configurable range so networking can be tested and documented.

Example defaults:

```text
GCS/head:                    6379
Node manager:                6380
Object manager:              6381
Runtime environment agent:   6382
Dashboard agent gRPC:        6383
Worker ports:                10000-10199
Dashboard, local only:       8265
```

The exact port set may be adjusted after validating it against the pinned Ray release.

The same port contract must be used by the manager and every worker.

### 6.3 Authentication

The manager must use the supported CANFAR client authentication and server-selection mechanisms.

Requirements:

- Detect whether usable CANFAR client credentials and a server selection already exist.
- Display authentication status without exposing secrets.
- Provide a supported way for the user to complete `canfar login`.
- Prefer an embedded terminal or device-style login flow over collecting passwords in a custom form.
- Store authentication state only using the existing `canfar` client configuration behavior.
- Never store credentials in:
  - the container image;
  - `/arc/projects`;
  - cluster state JSON;
  - application logs;
  - browser local storage.
- Apply restrictive permissions to any manager-owned state directory.

For the MVP, it is acceptable for the user to authenticate interactively once from a manager-provided terminal. The implementation must document this clearly.

### 6.4 Cluster creation

The UI must allow the user to specify:

- cluster name;
- project name or working directory;
- worker image;
- CPU or GPU worker type;
- worker count;
- CPU cores per worker;
- RAM per worker in GB;
- GPUs per worker;
- startup timeout;
- minimum acceptable joined-worker count;
- behavior when only some workers start:
  - fail and clean up;
  - accept partial capacity;
  - continue waiting.

The backend must:

1. Generate a unique cluster ID.
2. Persist an initial state record.
3. Launch workers with `canfar.sessions.Session.create`.
4. Store all returned CANFAR session IDs.
5. Poll CANFAR session status.
6. Poll Ray node membership.
7. Mark a worker ready only after it is both:
   - running in CANFAR;
   - alive in Ray.
8. Surface session events and logs when startup fails.
9. Clean up partially started workers according to the selected policy.

### 6.5 Cluster status model

Track these states separately:

```text
Requested
CANFAR Pending
CANFAR Running
Ray Joining
Ray Healthy
Ray Unhealthy
CANFAR Failed
Stopping
Stopped
Orphaned
```

The UI should show, per worker:

- CANFAR session ID;
- CANFAR status;
- Ray node ID when joined;
- requested CPU, RAM, and GPU;
- worker IP;
- last heartbeat;
- last error;
- log link or log excerpt.

### 6.6 Cluster stop and cleanup

The manager must:

- destroy all recorded worker sessions using the CANFAR client;
- wait until they are no longer active;
- mark the cluster stopped;
- preserve a concise history record;
- remove temporary manager-side state that is no longer required.

Provide:

- **Stop cluster**;
- **Force cleanup**;
- **Clean orphaned workers**;
- **Retry failed worker**.

Never identify worker ownership by session name alone. Use recorded session IDs and cluster IDs.

### 6.7 Persistence and recovery

Persist state under:

```text
/arc/home/<user>/.canfar-ray/clusters/<cluster-id>/
```

Suggested files:

```text
state.json
events.jsonl
manager-heartbeat
```

Requirements:

- directory permissions: user-only;
- atomic state updates;
- no credentials in persisted state;
- on manager restart, load previous non-terminal clusters;
- query the CANFAR API to reconcile actual session state;
- query Ray to reconcile joined nodes when the head is still valid;
- offer cleanup when the previous cluster cannot be recovered.

---

## 7. Worker Contract

Every worker receives configuration through environment variables.

Required variables:

```text
RAY_CLUSTER_ID
RAY_HEAD_IP
RAY_HEAD_PORT
RAY_VERSION_EXPECTED
RAY_WORKER_CPUS
RAY_WORKER_GPUS
RAY_SPILL_DIR
RAY_MANAGER_HEARTBEAT_PATH
RAY_MANAGER_HEARTBEAT_TIMEOUT_SECONDS
```

Optional variables:

```text
RAY_NODE_MANAGER_PORT
RAY_OBJECT_MANAGER_PORT
RAY_RUNTIME_ENV_AGENT_PORT
RAY_DASHBOARD_AGENT_GRPC_PORT
RAY_MIN_WORKER_PORT
RAY_MAX_WORKER_PORT
RAY_LOG_LEVEL
```

The worker entrypoint must:

1. Validate all required values.
2. Verify **`/scratch`** and shared **`/arc/home/<user>`** (for manager heartbeat). Do not require the `/arc` mount root.
3. Confirm that the installed Ray version matches `RAY_VERSION_EXPECTED`.
4. Determine its pod IP.
5. Test TCP connectivity to the Ray head.
6. Create the spill directory.
7. Start the Ray worker in blocking mode.
8. Monitor the manager heartbeat.
9. Exit non-zero on configuration or connectivity failure.
10. Exit cleanly when the head disappears or the heartbeat is stale.

The worker must not call the Kubernetes API.

---

## 8. Network Preflight

Networking is the first go/no-go gate.

Implement a manager preflight that:

1. Starts a temporary TCP listener on the manager on each required Ray port, or on a representative subset.
2. Launches one minimal headless probe session.
3. Passes the manager pod IP to the probe.
4. Tests worker-to-manager connectivity.
5. Obtains the worker pod IP from the probe output or a callback.
6. Tests manager-to-worker connectivity.
7. Tests a small range of worker ports.
8. Destroys the probe session.
9. Produces a clear pass/fail report.

Example report:

```text
Manager pod IP: 10.x.x.x
Worker pod IP:  10.x.x.x

Worker -> manager:6379       PASS
Worker -> manager:6380       PASS
Manager -> worker:6380       PASS
Worker port range sample     PASS
DNS dependency               NOT REQUIRED

Result: Ray cluster networking supported
```

If this preflight fails, the manager must not launch a full Ray cluster.

---

## 9. Ray Configuration Requirements

### 9.1 Head node

- Use zero schedulable CPUs by default.
- Use a fixed node IP.
- Use bounded, explicit ports.
- Store temporary state and spill data in `/scratch`.
- Keep the dashboard bound locally unless it is proxied safely through the manager application.
- Do not expose unauthenticated Ray Client or dashboard ports publicly.

### 9.2 Workers

- Set Ray CPU resources from the CANFAR CPU request.
- Set Ray GPU resources from the CANFAR GPU request.
- Do not overstate CPU or GPU resources.
- Use local `/scratch` for spilling and task-local caches.
- Keep durable outputs on `/arc`.
- Avoid placing large FITS cubes or full training datasets directly into the Ray object store when file paths are sufficient.

### 9.3 Version compatibility

The following must be pinned and recorded in image labels:

- Python version;
- Ray version;
- manager application version;
- `canfar` package version;
- CUDA version for GPU images;
- ML framework version for GPU images.

The manager must reject worker images whose reported Ray version does not match.

---

## 10. Web Interface

The initial interface can be server-rendered or a small single-page application.

Required screens:

### 10.1 Overview

- manager health;
- CANFAR authentication status;
- Ray head health;
- manager pod IP;
- current Ray version;
- network preflight status;
- active and historical clusters.

### 10.2 Create cluster

- worker type;
- image;
- count;
- CPU;
- RAM;
- GPU;
- project path;
- partial-start policy;
- startup timeout.

### 10.3 Cluster detail

- cluster status;
- worker table;
- Ray resource summary;
- CANFAR status;
- session events;
- worker logs;
- distributed smoke-test action;
- stop and cleanup controls.

### 10.4 Authentication

- current authentication context;
- current CANFAR server selection;
- login action;
- logout or reset action;
- no secret values displayed.

### 10.5 Diagnostics

- `/arc` write test;
- `/scratch` write and throughput test;
- `/dev/shm` size;
- manager and worker Ray versions;
- pod-to-pod network result;
- GPU visibility;
- CANFAR API reachability.

Do not expose arbitrary shell execution in the normal UI. An embedded terminal, if included for authentication and debugging, must be treated as an explicit advanced feature.

---

## 11. Security Requirements

- Run as the CANFAR-injected non-root user.
- Do not require privileged containers.
- Do not require Linux capabilities.
- Do not require Kubernetes service-account tokens.
- Do not mount the Docker socket.
- Do not include static CANFAR credentials.
- Do not log tokens, certificates, passwords, or authorization headers.
- Validate all submitted image references.
- Validate numeric resource inputs and impose configurable maxima.
- Escape all user-supplied values before invoking subprocesses.
- Prefer Python subprocess argument arrays; do not build shell command strings.
- Store manager state with user-only permissions.
- Restrict the manager API to the authenticated contributed-session user.
- Do not expose the Ray GCS, dashboard, or Ray Client ports through ingress.
- Treat Ray as trusted-code execution for the owning user, not as a multi-tenant security boundary.
- Document that all Ray workers belong to the same CANFAR user and inherit that user's project access.

---

## 12. Observability

### 12.1 Manager logs

Log:

- cluster ID;
- worker session IDs;
- state transitions;
- CANFAR API failures;
- network test failures;
- Ray node join and departure;
- cleanup results.

Redact:

- tokens;
- certificates;
- cookies;
- authorization headers;
- private registry secrets.

### 12.2 Worker logs

Log:

- Ray version;
- worker pod IP;
- head address;
- requested Ray resources;
- `/scratch` and `/dev/shm` capacity;
- connectivity results;
- Ray startup output;
- heartbeat expiration reason.

### 12.3 Health endpoints

Manager:

```text
GET /healthz
GET /readyz
GET /api/v1/status
```

`/readyz` should fail when:

- the manager app is running but the Ray head is unavailable;
- required storage is unavailable;
- local state cannot be written.

---

## 13. Sample Astronomy Workloads

Provide at least two examples.

### 13.1 Distributed FITS metadata scan

Input:

```text
/arc/projects/<project>/raw/**/*.fits
```

Behavior:

- pass file paths to Ray tasks;
- read FITS headers;
- return selected metadata;
- write a Parquet or CSV catalog under:
  `/arc/projects/<project>/results/<run-id>/`.

Acceptance target:

- work is distributed over at least two Ray workers;
- output is durable after the cluster is stopped;
- task logs identify which worker processed each file.

### 13.2 Distributed ML smoke test

Behavior:

- generate or load a small astronomy-shaped dataset;
- use Ray Train or Ray tasks on CPU;
- optionally use two GPU workers when available;
- write checkpoints under `/arc/projects/<project>/checkpoints/<run-id>/`;
- resume from the latest durable checkpoint.

This is a functional validation, not a performance benchmark.

---

## 14. Testing Plan

### 14.1 Container tests

- image builds without embedded secrets;
- required executables exist;
- `/skaha/startup.sh` exists and is executable;
- manager listens on port 5000;
- worker validates missing environment variables;
- manager and worker Ray versions match;
- images run as a non-root arbitrary UID.

### 14.2 Unit tests

- cluster-state transitions;
- state persistence and atomic writes;
- resource validation;
- command construction;
- secret redaction;
- CANFAR API error handling;
- partial-start policies;
- orphan detection.

Mock the CANFAR client and Ray state API.

### 14.3 CANFAR integration tests

Run in this order:

1. Launch manager contributed session.
2. Verify **`/arc/home/<user>`** and **`/scratch`** (not `/arc` root).
3. Complete CANFAR API authentication.
4. Run network preflight.
5. Launch one CPU worker.
6. Confirm CANFAR `Running`.
7. Confirm Ray node joined.
8. Run a two-node Ray smoke task.
9. Add a second worker.
10. Confirm resources increase.
11. Remove one worker.
12. Stop the cluster.
13. Confirm all worker sessions are destroyed.
14. Restart the manager and reconcile saved state.
15. Kill the manager unexpectedly and verify heartbeat-based worker exit or orphan cleanup.
16. Test a worker image with a mismatched Ray version.
17. Test a worker that remains pending.
18. Test a worker that fails before joining.
19. Test project storage read/write permissions.
20. Test GPU visibility when GPU resources are available.

### 14.4 Failure-injection tests

- manager deleted while workers run;
- worker killed during task execution;
- manager heartbeat file becomes unavailable;
- head IP is incorrect;
- required Ray port is blocked;
- CANFAR credential expires;
- project storage becomes read-only;
- `/scratch` fills;
- one worker uses the wrong Ray version;
- partial worker admission;
- CANFAR API temporarily returns errors.

---

## 15. Acceptance Criteria

The prototype is accepted when all of the following are true:

1. A user can launch the Ray Manager as a contributed CANFAR application.
2. The manager starts a Ray head and serves its UI on port 5000.
3. The manager can authenticate to the current CANFAR API without embedded credentials.
4. Network preflight proves bidirectional manager/worker connectivity.
5. The manager can launch at least two headless CPU workers.
6. Workers join the Ray cluster using the manager pod IP.
7. The UI distinguishes CANFAR-running workers from Ray-joined workers.
8. A distributed FITS example runs across at least two workers.
9. Results written to `/arc/projects/...` remain after cluster shutdown.
10. Ray spill and temporary data use `/scratch`.
11. Stopping a cluster destroys all recorded CANFAR worker sessions.
12. Manager restart reconciles cluster state without losing worker session IDs.
13. Unexpected manager loss does not leave workers running indefinitely without detection.
14. Secrets do not appear in logs, images, state files, or project storage.
15. CPU and GPU worker images use the exact same pinned Ray version as the manager.
16. The documentation explains current limitations, especially:
    - pod-IP dependence;
    - session quotas;
    - non-atomic worker admission;
    - `/dev/shm` constraints;
    - lack of production autoscaling.

---

## 16. Delivery Milestones

### Milestone A — Images and local runtime

Deliver:

- base image;
- manager image;
- CPU worker image;
- local container tests;
- pinned dependency manifest;
- startup scripts.

Exit criterion:

- manager and worker can form a Ray cluster in a local container or Kubernetes test environment using the same environment-variable contract planned for CANFAR.

### Milestone B — CANFAR network and authentication proof

Deliver:

- contributed manager launch;
- CANFAR API authentication flow;
- network preflight;
- one worker launched and destroyed from the manager.

Exit criterion:

- one CANFAR headless worker joins the Ray head through direct pod networking.

This is the primary go/no-go milestone.

### Milestone C — Multi-worker lifecycle

Deliver:

- cluster creation UI;
- multiple workers;
- status reconciliation;
- stop and cleanup;
- persisted state;
- partial-start policy.

Exit criterion:

- a two-worker cluster can be created, used, stopped, and recovered after a manager restart.

### Milestone D — Astronomy workload

Deliver:

- distributed FITS example;
- storage and spill validation;
- user guide;
- troubleshooting guide.

Exit criterion:

- durable astronomy output is produced on `/arc` using at least two workers.

### Milestone E — GPU validation

Deliver:

- GPU worker image;
- GPU diagnostics;
- Ray GPU resource verification;
- small distributed-training smoke test.

Exit criterion:

- requested GPUs are visible to Ray and to the selected ML framework, with checkpoints written to `/arc`.

---

## 17. Required Deliverables

The external developer must provide:

- source repository;
- Dockerfiles;
- pinned dependency lock files;
- manager and worker source code;
- container build instructions;
- image publication instructions for `images.canfar.net`;
- automated tests;
- CANFAR deployment instructions;
- user guide;
- operator/debugging runbook;
- security notes;
- architecture diagram;
- list of all Ray ports;
- environment-variable reference;
- state-file schema;
- sample astronomy workloads;
- known-limitations document;
- demonstration checklist;
- release notes for the delivered version.

All images must be tagged with immutable version tags. Do not rely only on `latest`.

---

## 18. Handoff Questions the Developer Must Resolve

Before declaring the prototype production-ready, document answers to:

1. Are direct pod-IP connections allowed between contributed and headless sessions?
2. Are connections bidirectional over the complete required Ray port set?
3. Does the manager pod IP remain stable for the lifetime of the contributed session?
4. What authentication flow is practical inside a contributed web application?
5. Where does the current `canfar` client persist authentication state in this environment?
6. What active-session limit applies to the target CANFAR deployment?
7. What is the effective `/dev/shm` size in manager and worker sessions?
8. What `/scratch` capacity and performance are available?
9. Are worker pod IPs reused in ways that affect stale state?
10. How quickly are headless sessions cleaned up after termination?
11. Which CPU, RAM, and GPU combinations are schedulable in practice?
12. Which CUDA and driver versions are available on CANFAR GPU nodes?
13. Does the selected GPU framework match the platform driver/runtime?
14. Are network policies different between projects, users, or session types?
15. Which image registries and image names are permitted by the deployment?

---

## 19. Source References

The implementation should be reviewed against the current versions of:

- `opencadc/canfar`
  - `docs/platform/sessions/contributed.md`
  - `docs/platform/sessions/batch.md`
  - `docs/client/get-started.md`
  - `docs/cli/authentication-contexts.md`
  - `canfar/sessions.py`
  - `canfar/models/session.py`
- `opencadc/science-platform`
  - `helm/skaha-config/service-contributed.yaml`
  - `helm/skaha-config/ingress-contributed.yaml`
  - `helm/skaha-config/launch-headless.yaml`
  - `helm/templates/session-volumes.yaml`
  - `helm/templates/session-volumes-mounts.yaml`
  - `helm/README.md`

Key platform facts reflected in this plan:

- contributed applications expose port 5000 and use `/skaha/startup.sh`;
- durable data belongs under `/arc`;
- `/scratch` is ephemeral;
- headless sessions accept commands, environment variables, resources, GPUs, and replicas;
- contributed sessions receive a port-5000 Service;
- headless sessions are Kubernetes Jobs without user Kubernetes credentials;
- session admission and cleanup remain controlled by CANFAR.

---

## 20. Final Design Principle

Keep the prototype intentionally narrow:

> The Ray Manager is a user-owned contributed application that launches user-owned CANFAR headless sessions and coordinates them through Ray over internal pod networking.

Do not turn it into an alternate Kubernetes control plane.

The implementation should make later migration straightforward:

- preserve the web UI;
- preserve the cluster request model;
- preserve job and state concepts;
- replace only the backend that currently creates headless sessions with a future CANFAR-native `RayJob` or KubeRay service.
