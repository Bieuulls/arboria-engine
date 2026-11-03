# Proposed Contributor Task Board

**These are suggested issues to open after checking the current source tree.** They are not claims that corresponding GitHub issues or labels already exist. Maintainers should verify a task is needed, add a reproduction or acceptance test, and assign scope before posting.

## Good first issue — approachable

| ID | Proposed issue | Acceptance criterion |
| --- | --- | --- |
| GFI-01 | Add a public GPU + driver report template | A reproducible run records environment and build ID |
| GFI-02 | Document one clean Windows build | Tested by someone who did not author the code |
| GFI-03 | Add a clean Linux build checklist | Missing dependencies and limitations explicit |
| GFI-04 | Add benchmark JSON/schema validation | Corrupt/incomplete measurement rejected |
| GFI-05 | Add scene/asset hash recording | Every capture traced to correct asset version |
| GFI-06 | Improve shader variable documentation | Buffer offsets and intended units documented |
| GFI-07 | Write a "first render" tutorial | Newcomer reproduces a basic scene |
| GFI-08 | Build a small permission-cleared test asset set | License and source documented |

## GPU / Vulkan — advanced

| ID | Proposed issue | Acceptance criterion |
| --- | --- | --- |
| GPU-01 | Mixed-mesh GPU scene addressing | Three distinct meshes, one batch, correct geometry |
| GPU-02 | Visible-list capacity and overflow handling | No out-of-range GPU access under stress |
| GPU-03 | Resource generation and lifecycle | Churn tests pass without stale handles |
| GPU-04 | Persistent instance-buffer dirty updates | Fewer uploads, no stale transforms |
| GPU-05 | Indirect command GPU trace | Real commands and draws verified |
| GPU-06 | Async/readback telemetry isolation | No recurring forced sync on render path |
| GPU-07 | Hi-Z camera-cut/resize correctness | No false disappearance across transitions |
| GPU-08 | Workgroup size sensitivity study | Results reproduce on at least two GPU architectures |
| GPU-09 | Full-frame and per-pass timing validation | Timing values reconcile with profiling method |
| GPU-10 | Multi-material batching test | Correct material IDs with stable performance |

## Geometry / quality

| ID | Proposed issue | Acceptance criterion |
| --- | --- | --- |
| GEO-01 | DAG cut continuity reference cases | No visible gaps at tested transitions |
| GEO-02 | Deterministic silhouette-difference test | Reference masks compare repeatably |
| GEO-03 | Correct mirrored normal transforms | Test scene with negative/nonuniform scales |
| GEO-04 | Import/export UV/tangent parity | Round-trip of assets with material maps |
| GEO-05 | Controlled PBR comparison scene | Matched lighting/exposure, documented error |
| GEO-06 | Alpha-cutout foliage edge cases | Silhouette and shadow expectations tested |
| GEO-07 | Mixed Godot/ARBORIA occlusion test | Both occlusion directions correct |

## Streaming / memory

| ID | Proposed issue | Acceptance criterion |
| --- | --- | --- |
| MEM-01 | Physical page-residency metrics | Upload + eviction traced to real GPU resources |
| MEM-02 | Root-page fallback invariant | Geometry remains visible under missing-detail pressure |
| MEM-03 | Budget stress scene | Working set exceeds configured managed VRAM budget |
| MEM-04 | No stale references after eviction | GPU access validation and repeated churn pass |
| MEM-05 | Streaming profiling dashboard | Page faults, latency and stutters recorded |

## Tooling / AI / community

| ID | Proposed issue | Acceptance criterion |
| --- | --- | --- |
| TOOL-01 | Strict gate negative tests | Stale capture, leak, fake metric all rejected |
| TOOL-02 | Normalized experiment-memory schema | Patch + metrics + reason recorded and queryable |
| TOOL-03 | Ollama proposal sandboxing | Untrusted output cannot edit gates or execute arbitrary commands |
| TOOL-04 | Baseline/candidate run isolation | Independent worktrees, same scene/asset hashes |
| TOOL-05 | AMD/Intel compatibility reporting | Reproducible reports across GPU vendors |
| TOOL-06 | GPU screenshot comparison harness | Automatic coverage/depth comparison from real renders |
| TOOL-07 | Moderation and discussion onboarding | Respectful starter template and labels configured |

## Suggested labels

`good first issue`, `help wanted`, `graphics`, `vulkan`, `godot`, `shader`, `geometry`, `benchmark`, `streaming`, `memory`, `ai-tooling`, `documentation`, `testing`, `repro needed`, `blocked`, `priority: critical`.

**Maintainer note:** choose 5–8 genuine issues for the initial announcement. An enormous task list without reproducible contexts discourages contributors.
