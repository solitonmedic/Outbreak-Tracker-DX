// Purpose: reusable Decky frontend build configuration, adapted from the official template.
// Runtime/location: Node 24.19.0, decky/rollup.config.js; invoked by pinned pnpm.
// Inputs: src/, tsconfig.json and package dependencies; no environment options.
// Outputs: dist/index.js and any files emitted by @decky/rollup.
// Safety: builds frontend files only; no PINE, recordings, installation or workbook access.
// Run from repo-merged/: python3 decky/scripts/deck.py build (executes on the Deck).
// Check: build succeeds and the resulting ZIP contains outbreak-tracker/dist/index.js.
import deckyPlugin from "@decky/rollup";

export default deckyPlugin({});
