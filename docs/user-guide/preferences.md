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
  `hotkey` to find Shortcuts, `api key` to find AI, `sum` to find Calculate, or an action's name
  to find the extension that provides it.
- The sidebar has two groups: OpenClip's own pages (General, Appearance, Customize, Shortcuts,
  App Rules, Store, About), then a page for everything that provides actions — **AI, then the
  built-in actions, then your Custom Actions, then every installed extension**. What shipped with
  OpenClip comes before what you installed, and names sort alphabetically inside each of those.
- **About** carries every outward link: Website, Documentation, GitHub and Report an Issue.
- Anything you drill into — an action's settings, the icon chooser, a prompt — opens as a page in
  the same column. The **‹ ›** arrows in the toolbar (or `⌘[` / `⌘]`) move back and forward
  through the pages you visited, exactly like System Settings. Nothing opens in a popover or a
  sheet, and problems are reported inline at the top of the page rather than in an alert.

---

## Customize: the popup bar's layout

The **Customize** page does two things and nothing else: it sets the **order** of everything in
the floating popup bar, and it manages **custom groups**.

```
Settings > Customize
├── Drag a row to reorder the popup bar
├── Drop an action onto a group to add it; drag it out to remove it
├── Select several rows, then + (or right-click › Create Group from Selection…)
└── Right-click a group › Configure Group… / Ungroup
```

Rows carry no switches or buttons. Double-clicking a row opens that action's own page, which is
where its name, icon, shortcut, options and enable switch live. The toolbar's **+** makes a
**New Group** from the selected rows.

### How Action Ordering Works
- Dragging actions changes their relative order in the floating popup bar.
- Action ordering is saved automatically via [`SettingsStore`](../../Sources/Core/Settings/SettingsStore.swift) under key `actionOrder`.

---

## Shortcuts

**Shortcuts** lists every runnable action — built-ins, AI prompts, your custom actions, then one
group per installed extension — with a switch, an alias (type it in the palette to jump straight
to the action), a hotkey, and a **›** into the action's own page. Search filters by name, alias
or keyword.

## Built-in actions

Search, Copy, Cut, Paste, Calculate, Define, Add Event, Open Link, Reveal in Finder and Word
Completion each have a row in the sidebar's second group. The page has an **Enabled** switch,
the name and icon shown in the popup bar, the alias and hotkey, and any options the action
declares (Search's engine, for example). **Revert** discards unsaved edits; **Save Changes**
applies them.

## Custom Actions

Your own Open URL, Text Snippet and Shell Script actions live on the **Custom Actions** page:
each with a switch and a › into its editor, plus **Add Custom Action** (also the toolbar's **+**).
An action's page has **Duplicate** and **Delete Action…** in its footer.

## Store

**Store** browses the extension catalogue. The toolbar carries the search field — the system's, so
it collapses to a magnifier when the window is too narrow for it — and a **…** menu holding
**Install from File…** (for a `.openclipext` folder, `.zip` or script you already have) and
**Refresh Catalog**. The **All / Popular / New** filter sits at the top of the list it filters.

## Extensions

Every installed extension has a page under the sidebar's second group, opening with a hero: the
extension's icon, its name, what it does, and its version and author.

The extension's own controls sit in the toolbar, on the same line as the back and forward arrows:

- The **switch** on the right turns the whole package on or off.
- The **…** menu beside it holds **View README**, **Show in Finder** and **Uninstall Extension**.
  Uninstalling asks first, in a banner at the top of the page.

Below the hero are each of the extension's actions with its own switch and a **›** into that
action's settings, **Update** when the Store has a newer version, and — for an extension that
groups its actions behind one icon — **Name and Icon in Popup Bar**.

The same toolbar pattern applies to every page that is about one thing: **AI** has its switch
there, and an action's page has its switch plus **Duplicate** and **Delete Action** in the … menu.

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

The **Appearance** page shows a static preview of the floating popup bar and lets you style it. The preview is a fixed visual mock of the canonical action set (Search, Copy, Cut, Paste plus the AI Tools action) — it does **not** reflect your configured actions, ordering, or overrides, and hovering it never affects the real popup.

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
