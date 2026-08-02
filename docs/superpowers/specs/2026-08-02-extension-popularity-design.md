# Extension Popularity (Obsidian Model) — Design

**Date:** 2026-08-02
**Status:** Approved design, pending implementation plan

## 1. Problem

The extension store catalog shows a hardcoded `downloadCount: 0` for every extension
(`ExtensionsModels.swift` / `route.ts`). We want real popularity data so users can rank
and discover extensions, without standing up analytics infrastructure.

Obsidian solves this by letting **GitHub count downloads for free** (Release assets
track download counts) and aggregating those counts into a committed stats file that
the app reads. We will adopt the same model.

## 2. Goals

- GitHub repo remains the single source of truth for extensions.
- Contributors still only edit `Extensions/raw/<Name>.openclipext/`.
- Real, all-time download counts per extension surfaced in the store.
- No new backend infra beyond GitHub Actions + existing Vercel API.

## 3. Architecture Overview

```
GitHub repo (ganeshmshetty/openclip)
├── Extensions/
│   ├── raw/<Name>.openclipext/     ← contributors edit ONLY this
│   ├── <Name>.openclipext.zip      ← CI-built (keep for back-compat / direct installs)
├── extension-stats.json            ← committed, auto-updated nightly
└── .github/workflows/
    ├── build-extensions.yml        ← on push: zip folders + create/update releases
    └── update-stats.yml            ← nightly: sum release downloads → commit stats

Vercel API (route.ts)
└── reads extension-stats.json (cached) → returns downloadCount per extension

macOS app
└── unchanged; already renders item.downloadCount from the API
```

## 4. Release Strategy (Option A — per-extension version releases)

- Each extension version publishes under its own release tag: `<extension-id>@<version>`.
  Example: `apple-music@1.0.0`.
- The release asset is the built zip: `<Name>.openclipext.zip`.
- Creating a **new release per version** (never editing/replacing an existing release's
  assets) preserves GitHub's cumulative per-asset download counts.
- All-time downloads for an extension = sum of `download_count` across all releases
  whose asset name matches that extension's zip.
- Version is read from the extension's `openclip.json` (add optional `version` field,
  default `1.0.0`).

## 5. GitHub Actions

### 5.1 build-extensions.yml (on push to main, changes under `Extensions/`)

1. For each `Extensions/raw/*.openclipext/`:
   - `zip -rX` the folder → `Extensions/<Name>.openclipext.zip`
   - Read `version` from `openclip.json` (default `1.0.0`)
   - Tag = `<identifier>@<version>` (identifier from manifest, else `com.openclip.<name>`)
2. Create the tag/release if it does not exist; if it exists **and the zip is unchanged,
   skip**. If the same tag already has a release, create a new version tag instead
   (version bump required).
3. Upload the zip as a release asset.

### 5.2 update-stats.yml (scheduled nightly)

1. List releases via `GET /repos/{repo}/releases`.
2. For each release, for each asset: `asset.name` → extension id (strip `.openclipext.zip`),
   accumulate `asset.download_count`.
3. Write `extension-stats.json`:

```json
{
  "updatedAt": "2026-08-02T00:00:00Z",
  "downloads": {
    "com.openclip.applemusic": 1234,
    "com.openclip.googlemaps": 567
  }
}
```

4. Commit + push the file back to `main` (direct, no PR, matching how Obsidian's
   `community-plugin-stats.json` is maintained).

## 6. API Changes (`web/src/app/api/v1/extensions/route.ts`)

- Fetch `extension-stats.json` from the repo (cached like the catalog, e.g. revalidate
  hourly) alongside the catalog.
- Merge: `downloadCount: stats.downloads[item.id] ?? 0`.
- Remove the hardcoded `downloadCount: 0`.

## 7. App Changes

None required. `ExtensionItem.downloadCount` already exists and the store UI already
renders it (fallback `"New"` when `0`). No Swift changes.

## 8. Out of Scope

- Per-version stats UI, charts, or history (later).
- App-reported install telemetry (privacy + infra; explicitly rejected for now).
- Automatic version bumping / changelogs.

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Download counts reset on asset replacement | New release per version; never edit/replace an existing release's assets |
| Duplicate tag on version collision | CI bumps/errors; docs instruct version bump in `openclip.json` |
| Stats commit churn / merge conflicts | Nightly single-file commit; low frequency |
| GitHub API rate limits | Only run on `main` events + scheduled; small release count |
