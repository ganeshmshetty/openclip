# DMG Installer

`OpenClip.dmg` is a styled disk image: a rendered background, the app icon on the left, a
drop link to `/Applications` on the right, and an arrow between them. It is produced by
`scripts/make_dmg.sh`, which both `scripts/package_app.sh` and `scripts/release_update.sh`
call, so local packaging and CI releases always emit the same layout.

```bash
./scripts/make_dmg.sh /path/to/OpenClip.app build/OpenClip.dmg
```

There is nothing to install first. The script uses [`dmgbuild`](https://dmgbuild.readthedocs.io),
and bootstraps it into `build/.dmg-venv` on first run if it is not already on `PATH`.

## Editing the background

The background is **not a checked-in bitmap**. Its source of truth is
`assets/dmg/background.html`, plain HTML/CSS with an inline SVG arrow. Edit that file,
re-run the packaging script, and the PNG/TIFF are regenerated — no image editor, and the
diff stays reviewable.

`scripts/render_html_png.swift` rasterises it through WebKit at exact pixel dimensions:

```bash
swift scripts/render_html_png.swift assets/dmg/background.html /tmp/bg.png 660 380 2
```

The renderer takes `<input> <output.png> <width> <height> [scale]` and accepts any HTML or
SVG file, so it is also the right tool for other generated art in this repo.

`make_dmg.sh` renders at 1× and 2×, then merges both into one multi-representation TIFF
with `tiffutil -cathidpicheck`. Finder picks the 2× rendition on Retina displays, which is
what keeps the background from looking soft — a single 660×380 PNG is blurry on every
modern Mac, and a plain 1320×760 PNG is drawn at double size.

## Layout contract

These numbers appear in **two** places and must be changed together: the CSS custom
properties at the top of `assets/dmg/background.html` and the constants near the top of
`scripts/make_dmg.sh`.

| Value | Setting |
| --- | --- |
| Background canvas | 660 × 380 pt |
| Finder chrome allowance | 68 pt |
| Window size | 660 × 448 pt (canvas + chrome) |
| Icon size | 128 pt |
| Icon label text size | 13 pt |
| Icon row centre | y = 210 |
| `OpenClip.app` centre | x = 170 |
| `Applications` centre | x = 490 |

Finder positions are the **centre** of each icon, measured from the top-left of the window
content area. With a 128 pt icon the graphic spans ±64 pt around the centre and Finder
draws the label just below it, so the background must leave roughly y = 146…296 clear
across both icon columns.

## Why dmgbuild and not create-dmg

`create-dmg` styles a disk image by mounting it and driving Finder over AppleScript. That
needs a GUI session on the build machine, costs a fixed sleep plus a retry loop for "Resource
busy", and — the reason this repo moved off it — it writes an icon position for **every**
item on the volume, hidden ones included:

```applescript
set position of every item to {theBottomRightX + 100, 100}
```

Parking `.background` and `.VolumeIcon.icns` outside the window keeps them out of sight, but
Finder still counts them towards the scrollable area. Anyone browsing with hidden files shown
(**Cmd-Shift-.**) gets a horizontal scroll bar across the bottom of an otherwise finished
window. Repositioning them inside the window trades that for two stray icons sitting on the
artwork, and moving one near the left edge makes Finder nudge every icon inwards to fit its
label cell — which slides the app and the drop link out of alignment with the background.

No shipping DMG does either. Reading the `.DS_Store` of The Unarchiver, Steam, Minecraft,
Grammarly, Annotate and TrackWeight, every one of them stores positions for the app and the
`Applications` link and **nothing else**. An item with no saved position is auto-placed by
Finder in a free grid slot inside the window, so it can never widen the content box.

`dmgbuild` reproduces that exactly. It writes the `.DS_Store` directly through the `ds_store`
and `mac_alias` modules instead of driving Finder, so only the entries listed in
`icon_locations` get a position, and the build needs no GUI session at all — which also makes
the release workflow deterministic.

Two dmgbuild details worth knowing:

- `window_rect` is in **bottom-up Cocoa coordinates**. A small y puts the window near the
  bottom of the screen; the settings file passes `y = 100000` so Finder clamps it to the top,
  which is the one placement that is consistent across display sizes.
- The background lands at `/.background.tiff` (a hidden file at the volume root), not in a
  `.background/` folder as `create-dmg` does.

## Why the window is taller than the canvas

Finder draws the background at its **natural size**, anchored to the top-left of the
content area — it never scales it. If the image is larger than that area, the window gets
scroll bars, which is the single most common way a styled DMG ends up looking broken.

`window_rect` covers the whole window frame, and Finder chrome eats into it: a 28 pt title
bar always, plus a ~36 pt tab bar for anyone who leaves **View → Show Tab Bar** on. That
setting belongs to the person opening the DMG, so the safe move is to size the window for the
worst case (`CHROME_H = 68`) and let the canvas be shorter than the content area.

The leftover margin is then covered by Finder's own white icon-view background, which is
why **the canvas must bleed to pure white at its outer edges**. Keep the tint and texture
away from the border; a coloured edge turns that margin into a visible seam.

None of the shipping DMGs above compensate for this — Annotate's background is 660 × 400
inside a 660 × 400 window — so they scroll vertically for anyone with the tab bar enabled.

## Design rules

- **The palette comes from the marketing site**, not the app icon: accent `#0071e3`, ink
  `#1d1d1f`, secondary `#86868b`, on the SF Pro Display stack with tight tracking. The app
  icon's blue is `#0084FF`, close but not the same — match the site so the installer and
  getopenclip.app read as one brand.
- **Never draw the app icon or the Applications folder into the background.** Both are real
  Finder items placed on top of it; painting them in produces doubled icons. The background
  holds decoration only — headline, arrow, footer.
- **Keep the background light, and there is no dark variant to add.** Finder's background
  picture is a single static file. A multi-representation TIFF selects on *scale*, not
  appearance, and nothing else in the `.DS_Store` is appearance-aware — so a disk image has
  exactly two options: no background at all, in which case Finder adapts fully (dark window,
  white labels), or a custom background, in which case Finder pins the window to light-mode
  rendering. Icon labels stay black and the area around the canvas stays white even when the
  title bar is dark, which is what makes the white bleed above work in Dark Mode too.

  Shipping DMGs reflect that: of seven inspected, five are white or near-white (The
  Unarchiver, Grammarly, Annotate, Vorssaint, Minecraft). The two dark ones both pay for it —
  Steam and the Jagex launcher each paint a light plate into the background exactly where an
  icon label lands, so the black text stays readable. Going dark here would mean adopting
  that trick and keeping those plates aligned with `ICON_Y` by hand.
- The volume icon is generated from `assets/app-icon.png` via `sips` + `iconutil`, so the
  mounted volume shows the app's icon in the Finder sidebar and on the desktop.
- The window is intentionally free of a toolbar, status bar, path bar and sidebar, so it reads
  as a single instruction rather than a folder.
- The app's `.app` extension is **not** hidden, even though dmgbuild offers `hide_extensions`
  for it. That setting works by writing Finder's hidden-extension bit into a
  `com.apple.FinderInfo` extended attribute on the app bundle inside the image, and `codesign`
  treats that attribute as "resource fork, Finder information, or similar detritus not allowed":
  `codesign --verify --strict` then fails on the copy a user drags out of the DMG, while the same
  bundle verifies cleanly from the `.zip`. `scripts/release_update.sh` verifies the app inside the
  mounted image for exactly this reason. Finder hides `.app` extensions by default anyway, so the
  only people affected are those who turned "Show all filename extensions" on — who asked to see
  it.

## Verifying a change

```bash
./scripts/make_dmg.sh /path/to/OpenClip.app /tmp/OpenClip.dmg
open /tmp/OpenClip.dmg
osascript -e 'tell application "Finder" to tell disk "OpenClip"
  {bounds of container window, icon size of icon view options of container window,
   position of item "OpenClip.app", position of item "Applications"}
end tell'
```

Bounds should be 660 × 448, icon size `128`, positions `{170, 210}` and `{490, 210}`.

Finder will not enumerate the hidden items, so read the saved positions straight out of the
`.DS_Store` — this is the check that catches a returning scroll bar. Only the app and the
`Applications` link may appear:

```bash
python3 - <<'EOF'
import re, struct
d = open('/Volumes/OpenClip/.DS_Store', 'rb').read()
for m in re.finditer(b'Iloc', d):
    s = m.start()
    for n in range(1, 40):
        p = s - n * 2
        if p >= 4 and struct.unpack('>I', d[p - 4:p])[0] == n:
            print(d[p:s].decode('utf-16-be'), struct.unpack('>ii', d[s + 12:s + 20]))
            break
EOF
```

Then open the image four ways — Finder tab bar on and off, hidden files shown and not — and
confirm none of them shows a scroll bar.
