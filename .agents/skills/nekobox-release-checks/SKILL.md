---
name: nekobox-release-checks
description: Use before committing or publishing changes to NekoBox macOS applications, packaging scripts, or core distribution. Select evidence for the touched target and preserve the distinct main development branch and rm default branch.
---

# NekoBox macOS Release Checks

Read `docs/HANDOFF.md` first. Choose validation that matches the changed target rather than running unrelated checks.

## Branch and Remote Rules

- `main` is the active development branch.
- `rm` is the intentionally minimal GitHub default branch. Do not put normal source, build artifacts, or release work on it.
- `origin` is upstream; `macos` is the personal GitHub remote.
- Do not change GitHub defaults, visibility, feature settings, or branch protection as part of a release check without explicit authorization.

## Required Evidence

| Changed area | Minimum validation |
| --- | --- |
| `macOS/NekoBox` Swift sources | `cd macOS/NekoBox && swift build` |
| Native bundle script or resources | Swift build, `./Support/build-app.sh`, then inspect the generated app metadata and signature |
| Go core or gRPC contract | Run the focused Go build or tests for the changed package, plus regenerate or validate affected API bindings |
| Documentation, skills, or repository metadata | `git diff --check` and a manual scope review |

## Packaging Rules

`macOS/NekoBox/Support/build-app.sh` writes `NekoBox.app` under `macOS/NekoBox/.build`. Treat all `.build` output as generated. Never commit it.

Do not publish a bundle as distributable solely because it is ad-hoc signed. Distribution signing, notarization, update metadata, and release publication require their own explicit approval and evidence.

## Final Review

Run:

```sh
git diff --check
git status --short
```

Confirm that no generated artifacts, local state, `.zcode`, or unrelated user changes are staged. Summarize the commands actually run, their results, and any checks that could not run because of missing dependencies.
