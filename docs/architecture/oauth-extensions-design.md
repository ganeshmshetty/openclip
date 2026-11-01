# OAuth Sign-in for Extensions

Status: **proposed for 1.10.0** · Tracking issue: [#172](https://github.com/ganeshmshetty/openclip/issues/172)

## 1. Goal and scope

Extensions that call third-party APIs currently make the user paste a long-lived personal API key into
Preferences. This design moves credential handling into the host: OpenClip runs the OAuth authorization
code flow with PKCE in a system web authentication session, exchanges and refreshes tokens itself, and
hands an extension a short-lived access token.

In scope:

- Host-owned authorization, code exchange, token storage, and refresh.
- A manifest-declared provider reference and a JS bridge surface (`openclip.auth.*`).
- Linear as the first provider.
- API-key options remain fully supported as a fallback.

Non-goals:

- Client-credentials / server-to-server tokens.
- Letting an extension, or the user, supply a client ID, secret, or token endpoint.
- An OpenClip-operated token broker.
- OAuth for `shell`, `applescript`, `url`, `shortcut`, or `service` actions. Only JavaScript reaches the
  network inline, so only JavaScript can use the token.
- Multiple accounts per provider per package.
- Keychain storage. See §7 for why this deliberately diverges from the wording of issue #172.

## 2. Current state

| Area | Today | Consequence for this design |
| :--- | :--- | :--- |
| Secrets | `Sources/OpenClip/Platform/SecretStore.swift`: JSON dict at `~/.openclip/secrets.json`, `0600`, `NSLock`, `get/set/delete(account:)`. Keychain was removed on purpose (ACL prompts, signature mismatch). | Token storage plugs in here; no new storage mechanism. |
| Inbound URLs | `Sources/Core/Integration/OpenClipDeepLink.swift` parses `openclip://` with hosts `install` and `command/<name>`. Header states there is deliberately **no x-callback reply** because URL schemes are unauthenticated. | An OAuth callback cannot rely on this path alone; it needs in-process state validation (§8). |
| JS bridge | `Sources/OpenClip/Platform/Runtimes/OpenClipJSHost.swift` builds the `openclip` object, collects effects, pumps the run loop for async promises. `syncEvaluationGate` caps in-flight synchronous evaluations. | Adding `auth` is a bridge addition plus a restricted-preview exclusion. |
| Preview isolation | `installRestrictedPreviewEnvironment` replaces every effect function with a thrower before top-level code runs. | `auth` must join that list, or an inline preview could start a login. |
| Script budget | `JavaScriptAction.perform` passes `timeout: nil`, so ordinary JS actions run with no watchdog; inline preview passes a shorter UI budget. | A login promise can hold evaluation state indefinitely. This is why login is not script-driven (§4). |
| Manifest gate | `ManifestCapabilityGate` has an **empty** known set, so any `capabilities` entry rejects the package. `ManifestValidator` gates typed inline kinds and `displayOnly` on `InlineResultValue.minimumOpenClipVersion` (`"1.10.0"`, `Sources/Core/Actions/InlineResultValue.swift:80`). | A new `auth` block needs its own validator rule and the same min-version mechanism. |
| App shell | Not sandboxed (`OpenClip.entitlements` contains only automation); `LSUIElement: true`; `openclip` scheme registered in `project.yml`. | No network entitlement work; but an agent app must activate before presenting a browser sheet (§10). |
| Existing OAuth code | None. No `ASWebAuthenticationSession`, no token refresh anywhere in `Sources/`. | Greenfield. |

## 3. Provider reality check

This is the constraint that decides what 1.10.0 can promise.

**Linear (viable).** Supports PKCE with `code_challenge_method=S256`. With PKCE, `client_secret` is
**optional** in both the code exchange and the refresh call, so a distributed binary needs no secret.
Access token lifetime is 24 h (`expires_in` ≈ 86399); refresh returns a new access token *and* a new
refresh token, with a 30-minute replay grace for network retries. A revoke endpoint exists.
Source: <https://linear.app/developers/oauth-2-0-authentication>

**Atlassian 3LO — Jira / Confluence (not viable as-is).** Authorization code only; **no PKCE**. The
token endpoint requires `client_secret` on the initial exchange *and* on every refresh. Refresh tokens
rotate, expire after 90 days of inactivity, and allow a 10-minute reuse leeway. Shipping that secret in
an `.app` means it is extractable; a broker would be required instead. Atlassian's own guidance also
tells developers not to instruct customers to create individual 3LO apps.
Source: <https://developer.atlassian.com/cloud/jira/platform/oauth-2-3lo-apps/>

So 1.10.0 supports **PKCE public clients only**, which means Linear. Jira keeps its API-key path and
gets a separate follow-up decision (§11). Issue #172 asked for Jira "with PKCE"; that part of the request
is not satisfiable and should be answered on the issue rather than silently attempted.

## 4. Flow

Sign-in is started by the user in Preferences, never by a script:

1. Extension calls `openclip.auth.token("linear")`.
2. No usable credential → the call returns `null`. The extension calls
   `openclip.auth.requireSignIn("linear")`, which returns a `ConfigurationRequest`
   (`Sources/Core/Actions/ConfigurationRequest.swift`) so the popup closes and Preferences opens on that
   extension's page with a "Sign in to Linear" row.
3. User clicks **Sign in**. The host builds the authorize URL with its own `client_id`, the intersection
   of provider scopes and manifest scopes, a single-use `state`, and a PKCE S256 challenge.
4. An `ASWebAuthenticationSession` presents the provider's page. The session captures the custom-scheme
   redirect itself; the URL does not go through LaunchServices.
5. Host validates `state`, exchanges the code over `URLSession` **without** `client_secret`, and writes
   the credential as one atomic blob.
6. Later `openclip.auth.token` calls refresh single-flight when the access token is inside the skew
   window, replacing the whole blob so a rotated refresh token cannot be lost.

Why step 1 is not `openclip.auth.login()`: a login promise would (a) hold an in-flight evaluation and its
gate slot for as long as the user browses, (b) be cancelled when the popup is dismissed, and (c) run with
no watchdog (`timeout: nil`). Reusing the existing `openConfiguration` routing keeps the browser flow out
of the script sandbox and out of the popup's lifetime.

## 5. Manifest contract

Package level, alongside `minOpenClipVersion`:

```json
{
  "identifier": "com.example.linear-issues",
  "name": "Linear Issues",
  "minOpenClipVersion": "1.10.0",
  "capabilities": ["oauth"],
  "auth": [
    { "provider": "linear", "scopes": ["read"] }
  ],
  "actions": [ ... ]
}
```

Rules enforced by `ManifestValidator`:

- `provider` must exist in the host registry; unknown ids reject the package, matching how unknown
  action `type` strings behave.
- `scopes` must be a subset of that provider's allowlist. The host sends the intersection only; a
  manifest cannot escalate.
- The manifest cannot supply endpoints, `client_id`, or `redirect_uri`. Provider configuration is
  host-side, so an extension cannot redirect the authorization flow to an attacker's server.
- The block requires `minOpenClipVersion` at or above the release that ships the feature (§12).
- `capabilities: ["oauth"]` becomes the first entry in `ManifestCapabilityGate.knownCapabilities` and
  is surfaced in `ExtensionRiskProfile` / the install trust UI. The extension-catalog validator
  (`Extensions/scripts/validate.sh`) needs the same allowance in the other repository.

## 6. Bridge surface

| API | Returns | Notes |
| :--- | :--- | :--- |
| `openclip.auth.token(provider)` | access token string or `null` | Refreshes transparently inside the skew window. Never throws for "not signed in". |
| `openclip.auth.requireSignIn(provider)` | config-request result | Popup closes, Preferences opens at the extension's auth row. |
| `openclip.auth.status(provider)` | `{ authorized, expiresAt, scope }` | No token material. The `authorized` flag is what a UI hint should use; `format()` still needs the token. |
| `openclip.auth.logout(provider)` | `null` | Drops the stored credential, then best-effort revoke at the provider. |

All four must be added to `installRestrictedPreviewEnvironment`'s thrower list so automatic inline
previews cannot touch credentials or open a browser.

## 7. Storage

- New `OAuthCredentialStore` over `SecretStore`, one account key per package and provider:
  `oauth.<packageID>.<provider>`.
- The value is a **single** JSON blob (`access`, `refresh`, `expiresAt`, `scope`, `tokenType`,
  `accountLabel`) rather than several keys, so refresh rotation is one atomic
  `SecretStore.set` and a crash cannot leave an access token with a stale refresh token.
- Same security posture as existing secrets: `0600` file in `~/.openclip`. Issue #172 asks for Keychain;
  that was already tried and removed (`SecretStore.swift` header documents the ACL and signature
  problems). The plan keeps one storage mechanism and should say so on the issue.
- Cleared by the extension uninstall path, which already clears ordinary and secret options
  (see `docs/architecture/known-debt.md` → "Extension uninstall"). OAuth keys must join it, including
  for packages that are not currently loaded.
- Revoked/uninstalled packages must drop their credentials; a reinstall then requires a fresh sign-in.

## 8. Security model

| Threat | Mitigation |
| :--- | :--- |
| A package reads another package's token | Keys are namespaced by package id; the host answers only for the package id it is currently executing. `openclip.auth.token` cannot take a package argument. |
| An extension redirects the flow to its own server | Endpoints and `client_id` are host-owned; the manifest can only name a provider id and a scope subset. |
| Authorization code interception | PKCE S256 verifier held in memory only, single-use `state` nonce, provider code lifetimes (10 min) respected. |
| Foreign app replays a callback through the unauthenticated `openclip://` scheme | `state` must match a flow started in this process and be consumed once. `ASWebAuthenticationSession` normally captures the redirect before LaunchServices sees it; the deep-link path is defence in depth, not the primary capture. |
| Token material in logs | Provider id and package id only, at `.public`. Token strings are never interpolated into messages, including error paths. |
| Token exposure to extension JS | Inherent: the extension holds the bearer to call the API. Documented in the authoring guide; the trust badge (`capabilities: ["oauth"]`) is the user-visible warning. |
| Concurrent refresh invalidating a rotated refresh token | Single-flight per `(package, provider)`; providers give replay windows (Linear 30 min, Atlassian 10 min) that a single-flight design stays inside. |

## 9. Architecture placement

Core (no AppKit, no network — mirrors the existing Core/App split):

- `Sources/Core/Extensions/Auth/OAuthProviderID.swift` — typed provider identifiers and allowlisted scopes.
- `Sources/Core/Extensions/Auth/OAuthCredential.swift` — Codable credential value, expiry and skew math.
- `Sources/Core/Extensions/Auth/PKCE.swift` — verifier/challenge generation (CryptoKit is not UI, so it
  may live in Core) and `state` nonce generation.
- `Sources/Core/Extensions/Manifest/` — `auth` decoding in `ExtensionManifest.swift`, rules in
  `ManifestValidation.swift`, `oauth` added to `ManifestCapabilityGate`.

App:

- `Sources/OpenClip/Platform/Auth/OAuthSessionPresenter.swift` — `ASWebAuthenticationSession` plus the
  `ASWebAuthenticationPresentationContextProviding` anchor.
- `Sources/OpenClip/Platform/Auth/OAuthTokenService.swift` — authorize-URL construction, code exchange,
  refresh, revoke, all over an injected `URLSession`.
- `Sources/OpenClip/Platform/Auth/OAuthCredentialStore.swift` — the `SecretStore`-backed store from §7.
- `Sources/OpenClip/Platform/Auth/OAuthProviderRegistry.swift` — the Linear descriptor (endpoints, client
  id, scopes, revocation) and the lookup used by both validation and runtime.
- `Sources/OpenClip/Platform/Runtimes/OpenClipJSHost.swift` — `openclip.auth.*` wiring.
- `Sources/OpenClip/UI/Preferences/` — the auth row (provider name, status, Sign in / Sign out) on the
  extension configuration page.

## 10. Presentation details

- **Anchor window.** `ASWebAuthenticationSession` needs a presentation anchor: the Preferences window
  when sign-in starts there, otherwise the popup panel.
- **Agent app.** With `LSUIElement: true` the app is not active by default; activate before presenting or
  the browser sheet can open behind another app.
- **Ephemeral session.** `prefersEphemeralWebBrowserSession` avoids inheriting ambient Safari cookies, so
  the user picks the account deliberately. Cost: one sign-in per provider, which is fine because the
  refresh token persists.
- **Copy** goes through `String(localized:)` with entries in `Localizable.xcstrings` and the four
  translation JSONs, per `AGENTS.md`.

## 11. Open questions

1. **Linear custom-scheme redirect.** Register `openclip://oauth/callback` (or a dedicated
   `openclip-oauth://` scheme) in the Linear OAuth app and verify it is accepted. Evidence that custom
   schemes work (`cursor://anysphere.cursor-mcp/oauth/callback`) is indirect. If rejected, fall back to a
   loopback listener on `127.0.0.1` with an ephemeral port, which Linear's docs do show.
2. **Atlassian.** Options: keep API keys (cheapest, no new surface), or add a broker service (new
   operational surface, out of scope for 1.10.0). Recommendation: keep API keys and answer issue #172
   explicitly.
3. **Login entry point.** Preferences-only in v1, or also from the popup? From the popup the panel must
   survive the session and the popup must not steal focus back.
4. **`openclip.auth.token` return shape.** A bare string is simplest; an object with `expiresAt` lets
   scripts pre-refresh. Leaning to a bare string for v1.
5. **Revocation scope.** Whether sign-out revokes at the provider always, or only when the token is still
   valid.

## 12. Release sequencing for 1.10.0

`MARKETING_VERSION` is `1.10.0` (build 27) only on `feat/typed-inline-results` (PR #207); `main` is at
`1.9.2` (build 26). `minOpenClipVersion` is **min-only and decode-only**: an extension that declares
`1.10.0` loads on a `1.10.0` build regardless of whether that build has the feature, then fails at
runtime with a `TypeError` — precisely the "Needs Update" confusion the gate exists to prevent.

Therefore one of:

- **A (recommended):** OAuth implementation merges before the 1.10.0 build is cut, and both the host
  constant and the catalog validator use `"1.10.0"`.
- **B:** OAuth slips to the next version; the gate becomes `"1.10.1"`/`"1.11.0"` in the host constant,
  `project.yml`, and the catalog validator, in the same change.

Any intermediate state (gate says 1.10.0, feature not in that build) is the one thing to avoid.

## 13. Acceptance and tests

Core unit tests:

- PKCE S256 against the RFC 7636 test vector; verifier length and charset.
- Manifest: valid block accepted; unknown provider rejected; scope outside the allowlist rejected;
  `auth` without a sufficient `minOpenClipVersion` rejected; `capabilities: ["oauth"]` accepted while
  other capability strings still reject.
- Credential expiry/skew boundaries, and that a rotated refresh token replaces the whole blob.

Host tests (injected `URLSession` via `URLProtocol`, injected presenter so CI never opens a browser):

- Exchange success, `invalid_grant`, network error, and revoked-token 401 on refresh.
- Refresh single-flight: two concurrent `token` calls trigger one refresh.
- Missing credential → `null`, and `requireSignIn` → `ConfigurationRequest` for the right action.
- Restricted preview: every `openclip.auth.*` call throws.
- `state` mismatch and replayed `state` are rejected.
- Uninstall clears the credential; other packages' credentials survive.

Manual: sign in to Linear from Preferences, run a real action, restart (token persists), force expiry with
a short-TTL stub, sign out, and confirm the extension falls back to the sign-in prompt.

Gates: `./scripts/test.sh`, `./scripts/lint_comments.sh`, `git diff --check`.

## 14. Docs and cross-repo work

- `docs/index.md` — link this document.
- `docs/architecture/known-debt.md` — extend the uninstall and secrets notes with OAuth credential
  clearing.
- `Extensions/AGENTS.md` and `Extensions/scripts/validate.sh` — **other repository**
  (`openclip-extensions`): document `auth`, add `oauth` to the allowed capabilities, and validate scope
  subsets. Nothing under `Extensions/` is committable here.
- `Sources/OpenClip/Resources/Localizable.xcstrings` plus `scripts/translations/{zh-Hans,zh-Hant,fr,ja}.json`
  → `python3 scripts/generate_localizable.py`.

## 15. Stop condition

1.10.0 ships with Linear PKCE sign-in: no plaintext credentials in manifests or defaults, tokens stored
at `0600` through `SecretStore`, refresh automatic and single-flight, automatic inline previews unable to
touch `auth`, uninstall clearing credentials, and Jira still on API keys with an explicit answer on
issue #172.
