# Preferences & Customization

OpenClip offers extensive customization for action ordering, display labels, custom icons, and AI provider integration through the Preferences window.

---

## Opening Preferences

You can open OpenClip Preferences in these ways:
- Click the OpenClip menu bar icon and select **Settings…**
- Press `Cmd + ,` while the OpenClip popup bar or settings window is focused.
- If the menu bar icon is hidden, open OpenClip again from Finder or Spotlight.

## General

The **Show Menu Bar Icon** toggle is enabled by default. Turning it off removes the icon
immediately without stopping OpenClip, its selection monitoring, or its global shortcut.

---

## Finding your way around

The settings window is laid out like System Settings:

- **Search** at the top of the sidebar filters the pages by name and by what they contain — type
  `hotkey` to find Shortcuts, `api key` to find AI, or an action's name to find the extension that
  provides it.
- The sidebar has two groups: OpenClip's own pages (General, Appearance, Actions, Shortcuts,
  App Rules, Store, About), then **AI and every installed extension**, one page each.
- Anything you drill into — an action's settings, the icon chooser, a prompt — opens as a page in
  the same column. The **‹ ›** arrows in the toolbar (or `⌘[` / `⌘]`) move back and forward
  through the pages you visited, exactly like System Settings. Nothing opens in a popover or a
  sheet, and problems are reported inline at the top of the page rather than in an alert.

---

## Action Catalog & Drag-and-Drop Reordering

The **Actions** page lists all available builtin actions, user-configured custom actions, and installed extension packages.

```
Settings > Actions
├── Drag a row to reorder actions in the floating popup bar (drop onto a group to add to it)
├── Toggle the switch to enable or disable individual actions
└── Click › (or double-click the row) to open that row's settings page
```

A row's **›** opens a page for what the row is: an action opens its editor (name, icon, alias,
hotkey, options), a custom group opens the group editor, an extension's group row opens the
**extension's page**, and the AI Tools row opens the **AI** page. The toolbar's **+** offers
New Group, Add Custom Action and Install Extension…, each as a page.

### How Action Ordering Works
- Dragging actions changes their relative order in the floating popup bar.
- Action ordering is saved automatically via [`SettingsStore`](../../Sources/Core/Settings/SettingsStore.swift) under key `actionOrder`.

---

## Extensions

Every installed extension has a page under the sidebar's second group. It shows the extension's
icon, version, author and description, a switch for the whole package, each of its actions with
its own switch and a **›** into that action's settings, **Update** when the Store has a newer
version, **Show in Finder**, and **Remove Extension…** (confirmed inline). For an extension that
groups its actions behind one icon, **Name and Icon in Popup Bar** renames the group or changes
its icon.

---

## Customizing Action Titles & Icons

OpenClip allows overriding the display title and icon for any action without editing code or manifests.

### Display Overrides via `ActionCustomizationManager`
- **Custom Title**: Override the default name displayed in popup tooltips or preferences tables.
- **Custom SF Symbol**: Enter any valid macOS SF Symbol name (e.g. `sparkles`, `doc.on.doc`, `terminal`).
- **Custom Text Icon**: Display a 1–2 character text icon instead of a symbol.

All overrides are managed via [`ActionCustomizationManager`](../../Sources/Core/Actions/ActionCustomizationManager.swift) and stored persistently in `SettingsStore`.

---

## Popup Appearance & Theme

The **Appearance** tab shows a static preview of the floating popup bar and lets you style it. The preview is a fixed visual mock of the canonical action set (Search, Copy, Cut, Paste, Services plus the AI Tools action) — it does **not** reflect your configured actions, ordering, or overrides, and hovering it never affects the real popup.

### Popup Theme
The theme control has two labeled rows:

1. **Category** — **Classic** (solid color themes) or **Glass** (a frosted material surface: Liquid Glass on macOS 26+, a standard frosted material on macOS 14–15).
2. **Appearance** — **System**, **Light**, or **Dark**. This appearance is shared by both categories (Glass adapts to it too — Glass is a material, not a color).

The preview always reflects the active combination, and a pinned appearance forces the popup's `colorScheme` so the material *and* the content colors flip together.

> [!NOTE]
> The Liquid Glass effect requires macOS 26+. On macOS 14–15 the Glass option renders as an `.ultraThinMaterial` frosted surface.

---

## AI Provider Setup

OpenClip includes an AI assistant overlay that processes text selections using local or cloud AI models.

Select **AI** in the sidebar (the first row of the Extensions group) to turn AI Tools on or off and configure your provider:

| Provider | Description | Setup Requirements |
| :--- | :--- | :--- |
| **Apple Intelligence** | On-device macOS intelligence framework | macOS 15.0+ with Apple Intelligence enabled |
| **Ollama (Local)** | Privacy-focused local LLM execution | Running Ollama instance (`http://localhost:11434`) |
| **Cloud AI (OpenAI / Claude / Gemini / DeepSeek / Groq / OpenRouter / Custom)** | Cloud API language models | Valid API Key stored securely in `SecretStore` (`~/.openclip/secrets.json`) |
| **Browser Redirect** | Opens AI query in browser | No API key required |

### Ask AI from the search palette

Anything you type into the action-search palette (⌥⌘C, or the ⌘ button on the popup bar) that
matches no action is offered to AI instead of a "No matches" notice:

- **Ask AI: “…”** runs your text as an instruction on the selected text — select a paragraph,
  type `rewrite to slovak`. Press **⏎** (or ⌘1) to see the answer in the result card, with a
  diff of what changed, then paste or copy it. Press **⇧⏎** and the answer **replaces the
  selection** the moment it lands instead (a "Replacing…" toast shows meanwhile; if the app can't
  paste, or you've switched apps, the answer is copied).
- **Save as AI tool** (⌘2) keeps the instruction as a custom AI action and runs it the same way.
  From then on it appears in the palette by name, in the AI Tools bar, and under
  **Settings › AI › AI Actions**, where opening it renames it, edits its prompt, or deletes it.
- Your **recent instructions** are palette rows too: type any part of one (`slo` finds
  `rewrite to slovak`) and run it with ⏎ or ⇧⏎ like the Ask AI row. Eight are kept; a saved
  instruction leaves the list.

The rows appear only while AI is switched on; the instruction is sent to whichever provider is
configured above.

### Refine an answer in the result card

Every AI result card has an instruction field above its Copy and Paste buttons. Type what to
change — `shorter`, `more formal` — and press **⏎**: AI runs on the current answer and the card
updates in place. The diff always compares your original selection with the latest answer, so
after five follow-ups you still see the net change. Each follow-up also sees the session so far — the
original selection and what you asked before — as context, so "keep the greeting" or "same tone
as before" works. Chain as many refinements as you like; Paste always pastes the latest answer
over the selection. ⏎ on an empty field pastes as before.

### AI Settings Channel
AI settings are managed through `AIServiceManager` and isolated to ensure security and privacy.
