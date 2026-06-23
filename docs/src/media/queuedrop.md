# queuedrop (browser extension)

Source in `tools/queuedrop/`. A **PureScript** Manifest-V3 browser extension
(cross-browser via `webextension-polyfill`) that queues the current page/link
URL to a self-hosted queue endpoint — "send this to the media server" from the
browser.

> Doubles as the seed of a reusable PureScript WebExtension toolchain.

## Layout

```text
tools/queuedrop/
├── extension/
│   ├── src/
│   │   ├── WebExt.purs/.js     # FFI over the WebExtension API (polyfill)
│   │   ├── Queue.purs/.js      # pure HTTP/JSON client (no WebExt deps → node-testable)
│   │   ├── Queue/Config.purs   # endpoint/token from sync storage
│   │   ├── Background.purs     # service worker: toolbar + context-menu + content msg
│   │   ├── Content.purs/.js    # injects a floating "⬇ Queue" button on SC/YT pages
│   │   ├── Options.purs/.js    # options page (endpoint + token)
│   │   └── QueueTest.purs      # node smoke test of the compiled client
│   ├── static/                 # manifest.json, options.html, icons (rendered from icon.svg)
│   ├── spago.dhall/packages.dhall
│   └── build.sh                # spago build → esbuild-bundle 3 entry points → dist/
└── server/stub.py              # the queue endpoint contract, stubbed
```

## Build

`node_modules` / `output` / `.spago` / `dist` are gitignored — built artifacts.

```sh
cd tools/queuedrop/extension
npm install                                  # webextension-polyfill
nix-shell -p purescript spago nodejs esbuild --run ./build.sh
# load extension/dist as an unpacked extension:
#   Firefox  → about:debugging → This Firefox → Load Temporary Add-on → dist/manifest.json
#   Chromium → chrome://extensions → Load unpacked → dist/
```

> Note: the repo ships the **Dhall-era** spago (`spago.dhall`/`packages.dhall`),
> matching nixpkgs' `spago` (0.21.x). The pure `Queue` module is deliberately
> split from WebExt deps so `QueueTest` runs under plain node.

## The queue endpoint contract

The extension POSTs to a small tailnet-only service (`server/stub.py` is the
reference stub):

```text
POST /queue   {"url": "<url>"}  ->  {"ok": true,  "id": <n>, "title": "<name>"}
                                    {"ok": false, "error": "<msg>"}
GET  /healthz                   ->  {"ok": true}
```

Auth: optional `Authorization: Bearer <token>`. Configured in the extension's
options page. The stub logs/echoes; the real handler would call Pinchflat's
`Sources.create_source` (see [pinchflat](./pinchflat.md)) or drive the
[library pipeline](./pipeline.md) directly.

## Status

v0: builds, bundles validated, compiled `Queue.queueUrl` smoke-tested against
the live stub. **Not yet deployed** as a NixOS service — the queue endpoint is
still the stub. Lint scoping for `tools/queuedrop/server/**` lives in
`ruff.toml`.
