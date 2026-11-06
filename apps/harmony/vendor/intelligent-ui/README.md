# Pinned Intelligent UI renderer

This is the same renderer revision pinned by the upstream Android release workflow.

- Repository: https://github.com/dreamfarer-space/deepseek-harness-intelligent-ui
- Commit: `f3735efffd823f8c34817f4e8554743ac3276225`
- Source artifact: `dist/renderer.js`
- Git blob: `ebac4a4c2199383458d4e1fa2121be0e6043c5c0`
- License: see `LICENSE`, also copied into the HAP raw resources.

`scripts/build-surfaces.mjs` verifies the exact Git blob before packaging. No runtime download or missing-renderer fallback is used. Native action handling still requires the current token, artifact identity, version and session, followed by user confirmation for sending text.
