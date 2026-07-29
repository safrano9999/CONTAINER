---
name: fastpatch
description: Rapidly port and publish the existing deterministic OpenClaw patch for a new stable OpenClaw version without repeating broad research or a full release build.
---

# Fast OpenClaw Patch

1. Fetch the requested upstream stable tag and apply the existing deterministic patch unchanged.
2. Compare only the files touched by the patch. If it applies cleanly, do not redesign or investigate unrelated code.
3. Run the focused model-resolution tests and one `dummy/dummy` smoke test. Do not run a full OpenClaw release build.
4. Build only the Docker runtime `dist` required to replace `/app/dist` in the official image.
5. Package `dist/`, create its SHA-256 file, tag `<version>-deterministic.1`, and publish both assets to `safrano9999/openclaw`.
6. Pin `OPENCLAW_IMAGE` to the same upstream version, then update the deterministic installer inputs in the `openclaw-ephemeral` repository.
7. Commit and push only that installer update. Report the release URL, asset name, and successful smoke test.

Stop immediately if the patch does not apply cleanly. In that case, show only the conflicting files before changing anything.
