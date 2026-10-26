## Summary of Changes

A clear and concise description of the architectural change, bug fix, or performance optimization.

## Motivation & Context

Why is this change required? What issue does it fix? (e.g. `Fixes #123`)

## Verification & Testing

Please describe the tests you ran to verify your changes:

- [ ] Native C++ backend builds cleanly (`build.bat` / `./build.sh`)
- [ ] CTest unit tests pass
- [ ] Local Unified CI passes (`ci_local.bat` / `tests/panel/panel.py --cli`)
- [ ] No regression in visual parity (LOD0 and reference comparisons checked)
- [ ] No memory or GPU resource leaks (clean shutdown confirmed)

## Performance & Telemetry (if applicable)

| Metric | Baseline | This PR | Delta |
| :--- | :--- | :--- | :--- |
| Frame Time (p95) | | | |
| GPU Render (p95) | | | |
| CPU Render (p95) | | | |
| Triangle Count | | | |

*Hardware tested on: GPU Model, Driver version, OS*

## Checklist

- [ ] My code adheres to the coding standards in [CONTRIBUTING.md](CONTRIBUTING.md)
- [ ] I have updated documentation or shaders accordingly
- [ ] No temporary files, credentials, or absolute local paths are committed
