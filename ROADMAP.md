# ARBORIA ENGINE — Community Roadmap

This roadmap expresses engineering priorities and research directions. It is **not a statement that any milestone is already shipped**. Each milestone is accepted only after its checks pass on the current repository revision.

## Phase A — Trust the baseline (critical)

**Goal:** everyone can establish what ARBORIA draws and how fast it draws it.

- [ ] Public, clean-checkout build instructions confirmed by at least one second machine.
- [ ] Reproducible Godot/Vulkan reference scenes with permission-cleared meshes.
- [ ] Strict gates rejecting errors, leaks, stale captures, fake counters and incomplete metrics.
- [ ] Valid frame/GPU timing instruments, with query latency and sampling methods documented.
- [ ] Comparison against Godot MeshInstance3D and MultiMeshInstance3D, at matched quality.
- [ ] Benchmark results accompanied by GPU/driver/build IDs and unmodified raw data.
- [ ] Public known-issues list tied to reproducible examples.

**Exit gate:** maintainers and one independent contributor can reproduce matching results within documented run-to-run variability.

## Phase B — Correct global geometry submission (critical)

- [ ] Mixed-mesh GPU scene uses the right geometry, material and instance for every cluster.
- [ ] No assumed `first_mesh` geometry for an entire heterogeneous batch.
- [ ] Bounded visible-cluster counts, no indirect command overflow.
- [ ] Safe resource generations and lifecycle during insert/delete/recreate.
- [ ] Efficient persistent instance buffers with dirty-range updates.
- [ ] No recurring synchronous readback in the normal render loop.
- [ ] Batching reduces CPU workload **and** passes full-frame/geometry-equivalence checks.

**Exit gate:** multi-mesh deterministic scene passes geometry, GPU, memory and regression checks.

## Phase C — Quality and Godot integration (high)

- [ ] Gap-free DAG selection, stable projected-error LOD, conservative visibility.
- [ ] Mixed-scene depth occlusion in both directions and verified reversed-Z behavior.
- [ ] Shadow solution documented honestly: native pass integration or explicit proxy/fallback.
- [ ] Normal/tangent/UV/material correctness across asset conversion and LOD changes.
- [ ] PBR comparisons with matched light/exposure/material inputs.
- [ ] Hi-Z reduces actual hidden work without making visible geometry disappear.

**Exit gate:** controlled visual and depth differences within documented tolerances.

## Phase D — Real virtual memory and content workflow (high)

- [ ] Geometry page table corresponds to real data on disk and in GPU memory.
- [ ] Streaming updates actual resource residency, not bookkeeping only.
- [ ] Root/fallback pages remain available across movement and low-memory pressure.
- [ ] GPU budget, eviction, upload/transfer and page faults are independently measurable.
- [ ] Import GLB/glTF/OBJ with accurate transforms, metadata and applicable PBR attributes.
- [ ] Reimport/cache failures and unsupported animation/deformation handled explicitly.
- [ ] Godot editor workflow can save, reopen and render a converted asset.

**Exit gate:** budgeted camera walkthrough and asset round-trip pass without geometry loss.

## Phase E — Community optimization platform (high)

- [ ] Ollama/local-model suggestions are isolated from acceptance criteria.
- [ ] Candidate patches execute in separate worktrees/sandboxes.
- [ ] Protected independent tests compare correct baseline/candidate scenes.
- [ ] Accepted experiments include code hash, assets, metrics, images, and GPU configuration.
- [ ] Failed experiments stay in the knowledge store for future contributors.
- [ ] No self-modifying code without review, traceability and rollback.

**Exit gate:** an intentionally bad optimization is rejected, a valid candidate can be accepted, and decisions reproduce on rerun.

## Phase F — Production-readiness research (future)

- [ ] Prolonged stress tests with scene churn, dynamic cameras and streaming.
- [ ] Portability investigation on more GPUs and platforms.
- [ ] Diagnostics, GPU crash recovery limitations and editor quality-of-life.
- [ ] Stable source/build packaging and release discipline.
- [ ] Documentation for game developers and technical artists.

## Longer-term research ideas (not implementation commitments)

- Dynamic/deformable virtualized geometry, skinning, morphs and animation.
- Real-time destruction and partially updated geometry clusters.
- Dense forests, procedural plants, foliage alpha/transparency strategies.
- Physics-aware asset metadata and collision/visibility cooperation.
- Multi-GPU and platform-portable backend exploration.
- Cross-engine portability, reusable renderer interfaces, standalone renderer research.
- Learned LOD policies, performance prediction and AI-assisted content optimization.
- Streaming geometry from large-world databases and planetary scenes.
- Developer-friendly asset inspection, visual debugging and GPU heatmaps.

The community should prioritize based on **measured need, available maintainers and clear value**, not feature-count alone.
