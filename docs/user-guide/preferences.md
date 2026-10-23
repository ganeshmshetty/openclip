# Preferences and customization

The Preferences window controls how actions are ordered and labeled, which icons they use, how the popup looks, and which AI provider OpenClip talks to.

## Opening Preferences

- Click the OpenClip menu bar icon and choose **Settings…**
- Press `Cmd + ,` while the popup bar or the settings window has focus.
- If the menu bar icon is hidden, open OpenClip again from Finder or Spotlight.

## General

**General** controls how OpenClip is summoned, how it launches, and its system integration.

- **Triggers**
  - **Appear Automatically** shows the popup bar as soon as you select text.
  - **Hold Mouse to Trigger** opens the popup when you press and hold the mouse button without moving the pointer. A drag-select doesn't count. This works whether or not **Appear Automatically** is on.
  - **Keyboard Shortcut** sets the global hotkey (default `⌥⌘C`) that toggles the popup and the search palette.
- **App**
  - **Show Menu Bar Icon** shows OpenClip in the menu bar. Turning it off removes the icon right away. OpenClip and its shortcut keep running.
  - **Start at Login** launches OpenClip when you log in.
- **Permissions**
  - **Accessibility Access** shows whether macOS has granted Accessibility access, which OpenClip needs to read selections and paste.

## Finding your way around

The settings window uses the macOS Liquid Glass look.

- The window has a translucent, blurred backdrop. A fixed-width sidebar with no border sits on the window background under the native window controls.
- A search field at the top of the sidebar filters pages and actions as you type, by name, alias, keyword, or setting.
- Each page and action has its own colored rounded-square icon.
- Settings details appear in an inset rounded card. Its header has back and forward buttons (`⌘[` and `⌘]`), breadcrumbs, and buttons for the current page.
- To record a shortcut, click its field. A popover shows the modifier keys as you press them and listens for the key combination.
- The sidebar lists the core pages (General, Appearance, Customize, Shortcuts, App Rules, Store, About), then AI, built-in actions, custom actions, and installed extensions.
- **About** holds the version, links, and update controls, including an **Update Channel** picker for the **Stable** and **Beta** feeds.

## Customize: the popup bar's layout

**Customize** does two things: it sets the order of everything in the popup bar, and it manages custom groups.

```
Settings > Customize
├── Drag a row to reorder the popup bar
├── Drop an action onto a group to add it; drag it out to remove it
├── Select several rows, then + (or right-click › Create Group from Selection…)
└── Right-click a group › Configure Group… / Ungroup
```

Rows have no switches or buttons. Double-click a row to open that action's own page, where its name, icon, shortcut, options, and enable switch live. The toolbar's **+** creates a **New Group** from the selected rows.

### Action order

Dragging an action changes its position in the popup bar. [`SettingsStore`](../../Sources/Core/Settings/SettingsStore.swift) saves the order automatically under the key `actionOrder`.

## Shortcuts

**Shortcuts** lists every runnable action: built-ins, AI prompts, your custom actions, and then one group for each installed extension. Each row has a switch, an alias (type it in the palette to jump straight to the action), a hotkey, and a **›** that opens the action's own page. Search filters by name, alias, or keyword.

## Built-in actions

Search, Copy, Cut, Paste, Calculate, Define, Add Event, Open Link, Reveal in Finder, and Word Completion each have a row in the sidebar's second group. The page opens with the same header an extension's page has, showing the action's icon and name. Below it are the name and icon shown in the popup bar, the alias and hotkey, and any options the action declares (Search's engine, for example). The action's switch is in the toolbar. **Revert** discards unsaved edits and **Save Changes** applies them.

## Custom actions

Your own Open URL, Text Snippet, and Shell Script actions are on the **Custom Actions** page. Each has a switch and a **›** into its editor. **Add Custom Action** (also the toolbar's **+**) creates a new one. An action's page has **Duplicate** and **Delete Action…** in its footer.

## Store

**Store** browses the extension catalog. The toolbar has the search field, which is the system's and collapses to a magnifier when the window is narrow. It also has a sort button (Featured, Name, Downloads, Recently Added) and a **…** menu with **Install from File…** (for a `.openclipext` folder, a `.zip`, or a script you already have) and **Refresh Catalog**.

Sorting reorders the catalog and never hides anything. **Featured** is the catalog's own order with the curated showcase on top, and it's the only sort that shows the Featured section.

## Extensions

Every installed extension has a page in the sidebar's second group. It opens with the extension's icon, its name, what it does, and its version and author.

The extension's controls are in the toolbar, on the same line as the back and forward arrows:

- The switch on the right turns the whole package on or off.
- The **…** menu next to it has **View README**, **Show in Finder**, and **Uninstall Extension**. Uninstalling asks first, in a banner at the top of the page.

Below the header are the extension's actions, each with its own switch and a **›** into that action's settings. You'll also see **Update** when the Store has a newer version, and **Name and Icon in Popup Bar** for an extension that groups its actions behind one icon.

Every page about a single item follows the same toolbar pattern. **AI** has its switch there, and an action's page has its switch plus **Duplicate** and **Delete Action** in the **…** menu.

## Action titles and icons

You can change the title and icon of any action without editing code or manifests. [`ActionCustomizationManager`](../../Sources/Core/Actions/ActionCustomizationManager.swift) manages the overrides and keeps them in `SettingsStore`.

- **Custom Title** replaces the name shown in popup tooltips and in Preferences.
- **Custom SF Symbol** takes any valid SF Symbol name, such as `sparkles`, `doc.on.doc`, or `terminal`.
- **Custom Text Icon** shows one or two characters instead of a symbol.

### Result delivery and clicks

When an action produces text, such as a transformation, a dictionary definition, or a calculation:

- **When finished** is set per action, on each action's settings page: **Show in card**, **Paste**, or **Copy**. By default each action uses the delivery mode its author recommends, for example **Show in card** for Define, or **Paste or Copy** for text actions that use the standard default.
- **Secondary click** (right-click or ⇧-click) follows the **Clipboard Invariant**. It copies the result to the clipboard, or shows it in a card if the primary action was a copy, so you can copy output without changing the default paste behavior. Secondary outcomes an action declares explicitly still take priority. If you set an action to **Show in card**, secondary clicks on its text results show the card as well.

## Popup appearance and theme

Under **Customize > Behavior**, turn off **Show Command Palette** to hide the ⌘ search button at the end of the popup bar. The search shortcut (⌥⌘C by default) still works. **Reset** brings the button back.

The **Appearance** page shows a static preview of the popup bar and lets you style it. The preview is a fixed mock of the standard actions (Search, Copy, Cut, Paste, and the AI Tools action). It doesn't reflect your configured actions, their order, or your overrides, and hovering over it never affects the real popup.

### Popup theme

The theme control has two rows:

1. **Category** is **Classic** (solid color themes) or **Glass** (a frosted material: Liquid Glass on macOS 26 and later, a standard frosted material on macOS 14 and 15).
2. **Appearance** is **System**, **Light**, or **Dark**. Both categories share this setting. Glass is a material, not a color, so it follows the appearance too.

The preview always shows the active combination. A pinned appearance sets the popup's `colorScheme`, so the material and the content colors switch together.

> [!NOTE]
> The Liquid Glass effect needs macOS 26 or later. On macOS 14 and 15 the Glass option uses an `.ultraThinMaterial` frosted surface.

## Actions per page

In Appearance, use the minus and plus stepper to choose 2 to 24 actions per page (default 6). This applies to the main bar and to group bars. Wide actions and smaller displays can still cause pagination before the chosen count is reached.

## AI provider setup

OpenClip can send selected text to a local or cloud AI model. Select **AI** in the sidebar (the first row of the Extensions group) to turn AI Tools on or off and choose a provider:

| Provider | Description | Requirements |
| :--- | :--- | :--- |
| Apple Intelligence | On-device macOS intelligence framework | macOS 26.0 or later on Apple Silicon, with Apple Intelligence enabled |
| Ollama (Local) | Local LLM execution, so text stays on your Mac | A running Ollama instance (`http://localhost:11434`) |
| Cloud AI (OpenAI, Claude, Gemini, DeepSeek, Groq, OpenRouter, Custom) | Cloud API language models | A valid API key, stored in `SecretStore` (`~/.openclip/secrets.json`) |
| Browser Redirect | Opens the AI query in your browser | No API key |

With the Ollama preset, OpenClip asks reasoning models (Qwen 3.5 and DeepSeek-R1, for example) to skip their thinking pass, so results arrive in seconds instead of minutes. The CLI presets do the same where the tool has a switch for it: Claude Code runs with `MAX_THINKING_TOKENS=0` and Codex CLI with `-c model_reasoning_effort=none`. GitHub Copilot and custom commands have no "off" level, so they keep their defaults.

AI settings are managed by `AIServiceManager` and kept isolated for security and privacy.

### Putting an AI preset on the popup bar

To put a preset you use often directly on the popup bar, open **Actions**, expand **AI Tools**, and drag the preset between the top-level actions. Its position is saved. To return it to the group, drop it onto the **AI Tools** row. Presets moved out of the group still appear in the full search palette, and their enable switches, aliases, and hotkeys keep working.

The switch next to **AI Tools** in **Actions** hides the group and its remaining commands. It doesn't turn off AI or any presets on the main bar. To move every command out of the group, right-click it and choose **Ungroup**, or use **Remove from Group** on a single command. An empty group disappears from the Actions list and the popup. To bring it back, right-click a standalone AI command and choose **Add to Group > AI Tools**, then drag more commands onto or inside the group. Hovering over AI Tools opens its commands, and clicking opens their scoped search.

### Editing a preset

Select a preset under **AI > AI Actions** to edit its icon, display name, **Icon/Text** mode, keyboard shortcut, search alias, and prompt. Changes save automatically and apply whether the preset is inside AI Tools or on the main bar.

**Add Custom AI Action** offers the same controls before you create the preset, with **Show as > Text** selected by default. They're saved when you click **Add Action**, which opens the editor for the new preset. Cancelling discards the draft, including its shortcut and alias.

### System prompt

Every AI action sends a system prompt before the action's own prompt. It says what OpenClip is asking the model to do and sets general rules: return only the result, follow the requested language and tone, keep the meaning when editing, and don't invent facts. You can rewrite this part under **AI > System Prompt**. The editor starts with the built-in text and saves as you type, and **Reset to Default** brings the built-in text back. Your text applies to every AI action, Ask AI, and result-card follow-ups, with every provider.

OpenClip always adds three things after your text, and you can't edit them: the action's prompt (as the *Task*), the rule that the selected text in the `<text>…</text>` block is material to work on and not instructions, and the answer format OpenClip uses to read the result.

**Example: reply in the sender's language.** Say you have an action that drafts replies ("Reply to this message, very friendly, same tone…"), and its prompt is written in German. It tends to answer in German even when the message you selected is in English, because the built-in rules tell the model to follow the task's language. Replacing that rule in the system prompt fixes it for every action at once:

```
You execute a user-defined action in OpenClip. Follow the task below.

1. Return only the requested deliverable, without greetings, preambles, or commentary about completing the task.
2. Always write in the language of the text inside the <text> block, even when the task is written in another language. Translate any content from the task into that language.
3. Keep the length proportionate to the text inside the <text> block unless the task asks otherwise.
4. Do not invent facts missing from the input.
```

The CLI providers (Claude Code, Codex, Copilot) add their own agent instructions, and OpenClip's system prompt reaches the model as part of the request, not as a real system message. Your rules still apply, but the model may follow them less strictly than with Apple Intelligence, local models, or the cloud APIs.

### Ask AI from the search palette

If what you type in the action-search palette (⌥⌘C, or the ⌘ button on the popup bar) matches no action, the palette offers it to AI instead of showing "No matches":

- **Ask AI: “…”** runs your text as an instruction on the selected text. Select a paragraph and type `rewrite to slovak`. Press **⏎** (or ⌘1) to see the answer in the result card with a diff of what changed, then paste or copy it. Press **⇧⏎** and the answer replaces the selection as soon as it arrives. A "Replacing…" toast shows while it works, and if the app can't paste or you've switched apps, the answer is copied instead.
- **Save as AI tool** (⌘2) keeps the instruction as a custom AI action and runs it. From then on it appears in the palette by name, in the AI Tools bar, and under **Settings > AI > AI Actions**, where you can rename it, edit its prompt, or delete it.
- Your recent instructions also show up as palette rows. Type any part of one (`slo` finds `rewrite to slovak`) and run it with ⏎ or ⇧⏎, as with the Ask AI row. OpenClip keeps eight, and a saved instruction drops off the list.

These rows appear only while AI is switched on, and the instruction goes to whichever provider you've configured.

### Refining an answer in the result card

Every AI result card has an instruction field above its Copy and Paste buttons. Type what to change, such as `shorter` or `more formal`, and press **⏎**. AI runs on the current answer and the card updates in place. The diff always compares your original selection with the latest answer, so after five follow-ups you still see the net change. Each follow-up also sees the session so far (the original selection and what you asked before), so "keep the greeting" or "same tone as before" works. You can refine as many times as you like, and Paste always pastes the latest answer over the selection. Pressing ⏎ on an empty field pastes as before.
