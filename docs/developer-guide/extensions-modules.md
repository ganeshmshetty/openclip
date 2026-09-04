# JS Extension Modules: `require()`, npm Bundling & TypeScript

This page is the author-facing contract for OpenClip's JS module runtime: splitting code across
local files with `require()`, bundling third-party libraries with npm/esbuild, and TypeScript. The
manifest schema itself lives in [`AGENTS.md`](AGENTS.md) (§3b); this page covers what runs and how
to build it.

---

## 1. Module mode (local multi-file, no build step)

A `javascript` action that runs from a file (`"script": "main.js"`) runs in **module mode**: the
CommonJS bindings `require`, `module`, `exports`, and `__dirname` are in scope, and the entry file
may load other files inside the package.

- `require('./lib/helper.js')` — resolve and load a local module.
- `module` / `exports` — the current module's export object (`module.exports` and its `exports`
  alias).
- `__dirname` — the package directory (of the entry file).

Note: the **entry script's** `require` base and `__dirname` are bound to the **package directory**,
not the entry file's directory — so a manifest `script: "src/main.js"` would resolve
`require('./helper.js')` against the package root, not `src/`. Keep entry scripts at the package
root (which both the plain `js` scaffold and `--with-npm` scaffold do). Child modules resolve
relative to their own file, Node-style.

Inline `scriptCode` actions keep the **legacy single-file behavior, byte-identical**: no `require`,
no `module`/`exports`/`__dirname`. If you need modules, use a `script:` file.

### 1a. Entry dispatch

Module mode finds the entry function in this order:

1. `module.exports` **is** a function → it is the entry.
2. `module.exports.action` is a function → it is the entry.
3. `module.exports.main` is a function → it is the entry.
4. an in-scope `action` function.
5. an in-scope `main` function.

The entry is called as `(selection, options)`, exactly like the single-file contract (§7 of
`AGENTS.md`). If nothing matches, the script still runs (top-level side effects) and resolves to
`.success`.

### 1b. Resolution & caching

`require` resolves **Node-style, relative to the requiring file's directory**:

- the exact file (`require('./lib/helper.js')`),
- else with `.js` appended (`require('./lib/helper')` → `./lib/helper.js`),
- else `index.js` in the directory (`require('./lib')` → `./lib/index.js`).

Modules are cached **per run** — a second `require` of the same resolved path returns the same
`exports`. Cycles resolve to partial exports, Node-style.

### 1c. Containment

A script's filesystem reach is **the extension package directory only**. The host resolves symlinks
before checking, then enforces the package boundary (`OpenClipModuleLoader` +
`Constants.isPathSafe`). A `require` that resolves outside the package — a `../` escape or a symlink
pointing out — throws, and the run surfaces as `.toast(.error)` with "resolves outside the
extension package". Absolute-path specifiers are rejected outright.

### 1d. Rejected specifiers

- **Bare specifiers** never resolve. Node builtins (`fs`, `os`, `path`, …) get an explicit message
  ("Node builtin … is not available to OpenClip extensions"); any other bare name
  (`require('lodash')`) gets "bundle npm libraries with esbuild".
- **Inline `scriptCode`** has no `require` at all.

---

## 2. The npm + TypeScript path

When you need third-party libraries or TypeScript, scaffold with `--with-npm`:

```bash
./scripts/new_extension.sh Demo --with-npm
cd Extensions/raw/Demo.openclipext
npm install         # once
npm run build       # after every edit to src/
./scripts/install_extension.sh Extensions/raw/Demo.openclipext
```

The scaffold writes a `package.json` (esbuild + TypeScript dev deps), `tsconfig.json`,
`src/main.ts`, and `src/openclip.d.ts`, and generates a manifest whose `script` points at
**`dist/main.js`**.

### 2a. Build contract

`dist/main.js` is the **shipped artifact**: the manifest's `script` targets it and the host loads
only that one file. The contract:

- `npm install` once (regenerates `node_modules`).
- `npm run build` after **every** edit to `src/` — the bundle is stale otherwise.
- THEN `install_extension.sh`.

`validate_extension.sh` enforces this: an npm package without `dist/main.js` fails install (exit 1,
"run 'npm install && npm run build'"), and a `dist/main.js` older than `package.json` or anything in
`src/` produces a rebuild warning.

### 2b. TypeScript: the bundle path only

TypeScript is supported **only through the bundle path**. esbuild transpiles `src/*.ts` into the CJS
bundle; the **host loader runs `.js` only** — the app never sees a `.ts` file, so a manifest `script`
must never point at one. Write TypeScript in `src/`, emit `dist/main.js`.

`npm run typecheck` (`tsc --noEmit`) is optional — a CI/editor aid, not part of the build. The
ambient `openclip.*` declarations live in `src/openclip.d.ts` (type-only; the runtime never reads it).

### 2c. Bundling third-party libraries

The bundle path is how you use libraries: `npm install` a **pure-JS** library, import it from `src/`,
and esbuild inlines it into `dist/main.js`. Known-good classes:

- **Lodash-style utilities** — `lodash`, `just-*`, `ramda`.
- **Markdown/HTML parsers & processors** — `marked`, `turndown`, `cheerio`.
- **Slugify / string helpers** — `slugify`, `change-case`.
- **Date libraries** — `date-fns`, `dayjs`.

Node builtins can **never** be bundled: the build's browser platform rejects them at build time.

---

## 3. Limitations

These are hard limits of the shipped runtime, not open questions:

- **No Node builtins.** The bundle is built with `--platform=browser --target=es2020`, which
  hard-rejects `require('fs')` and friends at **build time** (`Could not resolve "fs"`) — the builtin
  can never ship.
- **No native `.node` bindings.** esbuild rejects them at build time.
- **No DOM.** The runtime is JavaScriptCore — no `window`, `document`, or browser globals.
- **Mind the 60 s watchdog.** A never-settling async script is killed after
  `Constants.scriptTimeout` (60 s) and surfaces as an error status. Users can also click the loading toast anytime to cancel running scripts immediately.
- **JSC's global set is not Node's.** The host runtime is JavaScriptCore, not Node: expect the JS
  language and the `openclip.*` bridge, not Node globals. A few names overlap (`setTimeout`, `Buffer`)
  but with JSC semantics, not Node's — treat any reliance on Node-global behavior as a known
  limitation, and use the esbuild `--define` shim (below) for `process.env.NODE_ENV` rather than
  assuming it exists.

---

## 4. esbuild shims for browser-platform builds

Because the bundle is built for esbuild's browser platform, libraries that touch Node-global
expectations need shims at **build** time (these live in the `package.json` build script, not the
extension code):

- **`--define:process.env.NODE_ENV='"production"'`** — libraries that branch on
  `process.env.NODE_ENV` get a defined constant instead of a missing-global error.
- **`--external:<name>`** — keep a dependency external to the bundle. Rarely useful here (the host
  cannot provide Node modules); prefer to bundle.
- **`--inject:./shims.ts` / `--alias:...`** — inject a global (e.g. a minimal `process` stub) or
  alias a module to a local file, both from under `src/`.

---

## 5. Reference

- Module resolution & containment: `Sources/OpenClip/Platform/Runtimes/OpenClipModuleLoader.swift`.
- Module prelude/wrappers & entry dispatch: `Sources/OpenClip/Platform/Runtimes/OpenClipJSHost.swift`.
- Scaffold/validate scripts: `scripts/new_extension.sh`, `scripts/validate_extension.sh`.