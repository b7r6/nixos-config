# queuedrop

Queue the current page/link URL to your self-hosted media server (yt-dlp / Pinchflat) from the
browser. A PureScript MV3 browser extension + a thin queue endpoint.

## Layout

- `extension/` — the PureScript WebExtension (Manifest V3, cross-browser via
  `webextension-polyfill`).
  - `src/WebExt.purs` / `.js` — FFI over the WebExtension API (runtime, tabs, contextMenus, storage,
    notifications, action).
  - `src/Queue.purs` / `.js` — pure HTTP/JSON client for the queue endpoint (no WebExtension deps;
    node-testable).
  - `src/Queue/Config.purs` — endpoint/token loading from sync storage.
  - `src/Background.purs` — service worker: toolbar click + context menu + content-script message →
    queue.
  - `src/Content.purs` / `.js` — injects a floating "⬇ Queue" button on SoundCloud/YouTube pages.
  - `src/Options.purs` / `.js` — options page (set endpoint + token).
  - `static/manifest.json`, `static/options.html` — MV3 assets.
  - `build.sh` — `spago build` then esbuild-bundle each entry point → `dist/`.
- `server/stub.py` — the queue endpoint contract, stubbed. Echoes/logs queued URLs. The real handler
  will call Pinchflat's `Sources.create_source` via `bin/pinchflat rpc` (or run yt-dlp → the
  organize/enrich/tag pipeline).

## Build

```sh
cd extension
npm install                       # webextension-polyfill
nix-shell -p purescript spago nodejs esbuild --run ./build.sh
# load extension/dist as an unpacked extension (chrome://extensions or
# about:debugging in Firefox)
```

## Queue endpoint contract

```
POST /queue   {"url": "<url>"}   ->  {"ok": true, "id": <n>, "title": "<name>"}
                                     {"ok": false, "error": "<msg>"}
GET  /healthz                    ->  {"ok": true}
```

Auth: optional `Authorization: Bearer <token>`. Exposure: tailnet/LAN only.

## Status

- Extension builds; `dist/` bundles validated (parse + manifest).
- Compiled `Queue.queueUrl` smoke-tested against the live stub (`QUEUED ok: Melting Bismuth`).
- TODO: real backend handler (Pinchflat source-create); icons; load-unpacked test in a live browser;
  package the endpoint as a NixOS service on guccimane.
