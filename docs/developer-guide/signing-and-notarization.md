# Code Signing, Hardened Runtime & Notarization

How an OpenClip build goes from a local Release build to something macOS will open on a stranger's
Mac, and what each step is defending against.

Inspect any build with [Apparency](https://mothersruin.com/software/Apparency/) or the commands in
[Checking a build by hand](#checking-a-build-by-hand). A distributable build shows a Developer ID
signature, the hardened runtime enabled, a stapled notarization ticket, and a Gatekeeper verdict of
`Notarized Developer ID`.

---

## Two build modes

Signing is **opt-in**, and everything works without it.

| | Ad-hoc (default) | Developer ID |
|---|---|---|
| Apple Developer account | not needed | required |
| Network access | not needed | required (timestamp + notary) |
| Hardened runtime | yes | yes |
| Entitlements | yes | yes |
| Opens on another Mac | no | yes |
| Used for | local builds, tests, PR/fork CI | releases |

A fresh clone builds, packages, and runs with no certificate at all. The only thing an ad-hoc build
cannot do is leave the machine that produced it: Gatekeeper has nothing to trust, so it refuses to
launch. Everything else — the hardened runtime, the entitlements, the inside-out signing order — is
identical in both modes, so a contributor is exercising the same code path a release does.

```bash
./scripts/package_app.sh                                # ad-hoc
OPENCLIP_SIGN_IDENTITY=auto ./scripts/package_app.sh    # Developer ID signed
OPENCLIP_SIGN_IDENTITY=auto OPENCLIP_NOTARIZE=1 \
    ./scripts/package_app.sh                            # signed, notarized, stapled
./scripts/release_update.sh 1.4.0                       # full release; signing is mandatory
```

## Configuration

`scripts/signing_config.sh` resolves the identity, highest precedence first:

1. `--identity <name>` on `sign_artifact.sh` or `verify_signing.sh`
2. `OPENCLIP_SIGN_IDENTITY` in the environment
3. `keys/signing.env`, if it exists
4. `-` (ad-hoc)

`OPENCLIP_SIGN_IDENTITY=auto` picks the single `Developer ID Application` identity in the keychain
and fails if there is none or more than one, so `auto` can never silently pick a different team.

`keys/signing.env` is a gitignored shell fragment — the whole `keys/` directory is ignored — that
makes a local signed build a single command:

```bash
OPENCLIP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
NOTARY_KEY="$PROJECT_DIR/keys/AuthKey_XXXXXXXXXX.p8"
NOTARY_KEY_ID="XXXXXXXXXX"
NOTARY_ISSUER="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

Notary credentials come from one of three groups, and `scripts/notarize_artifact.sh` takes the
first that is complete:

| Group | Variables |
|---|---|
| Keychain profile | `NOTARY_PROFILE` (from `xcrun notarytool store-credentials`) |
| App Store Connect API key | `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER` |
| Apple ID | `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`, `NOTARY_TEAM_ID` |

The Key ID is the `XXXXXXXXXX` in the `AuthKey_XXXXXXXXXX.p8` filename. The Issuer ID is a UUID
shown above the key list in App Store Connect under **Users and Access › Integrations › Team
Keys**; it is not stored in the key file. `NOTARY_KEY` accepts either a path or the key text
itself, so a CI secret can be passed inline without ever touching the disk in a readable state.

## The pipeline

`scripts/release_update.sh` runs these in order. `scripts/package_app.sh` runs the same steps
minus the appcast.

1. **Build** — `xcodebuild`, universal, deliberately left **ad-hoc signed**.
2. **Sign** — `scripts/sign_artifact.sh` re-signs the finished bundle inside out.
3. **Verify architectures** — `scripts/verify_universal.sh`.
4. **Verify signature** — `scripts/verify_signing.sh --require developer-id`.
5. **Notarize and staple** — `scripts/notarize_artifact.sh`.
6. **Verify again** — `scripts/verify_signing.sh --require notarized`.
7. **Archive** — `ditto` the stapled bundle into the release `.zip`.
8. **Appcast** — Sparkle's `generate_appcast` signs the archive with the Ed25519 key.
9. **Disk image** — built from the stapled app, then signed, notarized, stapled, and verified in
   its own right.

Order is load-bearing in three places.

- **Signing before archiving.** Obvious, but it also means the build step never needs the
  certificate, so the slow part of a release can run before credentials are checked. The scripts
  resolve the identity up front anyway, because a missing certificate should be a five-second
  failure and not a five-minute one.
- **Stapling before archiving.** Stapling writes the ticket into the bundle. A zip cut beforehand
  would contain an unstapled app, and Gatekeeper would have to ask Apple at first launch — which
  fails for anyone offline or behind a filtered network. It also means the Sparkle signature and
  the Homebrew `sha256` describe the stapled bundle, because they are taken from the archive in
  step 7.
- **Appcast before the disk image.** `generate_appcast` scans the output directory for release
  archives, so the `.dmg` is built after it has run.

## Why the app is re-signed rather than signed by Xcode

The packaging scripts used to finish with `codesign --force --deep --sign -`. That single line
caused most of what needed fixing:

- `--deep` walks a bundle **outside in** and **discards the flags and entitlements** of everything
  it re-signs. project.yml had asked for `ENABLE_HARDENED_RUNTIME` for a long time, and Xcode
  honoured it — then this call replaced that hardened signature with a plain ad-hoc one. Apparency
  reported `Hardening: Not enabled` on a project whose settings said otherwise, and no check
  looked at the finished artifact.
- Apple's own guidance is to sign nested code individually, deepest first, so a container is
  sealed only once its contents are final. `scripts/sign_artifact.sh` does exactly that, using the
  one shared walk in `oc_nested_code_items` so the signer and the verifier can never disagree
  about what counts as nested code.

Handing the identity straight to `xcodebuild` instead is not sufficient either. A Release build
with `CODE_SIGN_IDENTITY` set to a Developer ID certificate produces:

- the app, `Core.framework`, and `Sparkle.framework` correctly signed, but
- **Sparkle's `Updater.app`, `Downloader.xpc`, `Installer.xpc`, and the `Autoupdate` helper still
  ad-hoc signed**, exactly as Sparkle ships them. Signing a framework seals its helper binaries as
  resources without re-signing them. One ad-hoc binary anywhere inside the bundle is enough for
  the notary service to reject the whole submission.
- **`com.apple.security.get-task-allow` injected into the entitlements.** Xcode adds this
  debugging entitlement to any non-archive build. It lets other processes attach a debugger to the
  app, and the notary service rejects submissions that request it.

Re-signing the finished bundle from a known state fixes both, and the verifier fails the build if
either ever comes back.

## Entitlements

`Sources/OpenClip/OpenClip.entitlements` grants exactly one thing:

```
com.apple.security.automation.apple-events
```

AppleScript actions drive other applications. `AppleScriptRunner` shells out to `/usr/bin/osascript`
rather than using `NSAppleScript`, and TCC attributes those Apple events to OpenClip as the
responsible process, so the app needs both this entitlement and the `NSAppleEventsUsageDescription`
string that `project.yml` puts in `Info.plist`.

Deliberately **not** granted:

| Entitlement | Why not |
|---|---|
| `com.apple.security.cs.allow-jit` | JavaScriptCore extensions run correctly under the hardened runtime without it. Measured: a hot three-million-iteration loop evaluates in the same time signed with `--options runtime` as unsigned. The W^X exception buys nothing here. |
| `com.apple.security.cs.disable-library-validation` | Nothing is `dlopen`'d. Extensions are JavaScript, shell, AppleScript, or URL templates — never native code. |
| `com.apple.security.cs.allow-dyld-environment-variables` | Script actions get their environment from `ShellProcessRunner`; nothing injects `DYLD_*` into OpenClip itself. |
| App Sandbox | Incompatible with Accessibility-based text capture, `CGEvent` key synthesis, `~/.openclip`, and arbitrary script actions. Notarization does not require it. |

Two rules when editing that file:

1. **No XML comments.** `codesign`'s entitlement parser (AMFI) rejects them outright with
   `AMFIUnserializeXML: syntax error`, and the build fails at the signing step. Rationale goes in
   this document, not in the plist.
2. `scripts/verify_signing.sh` compares the **signed** entitlements against this file and fails on
   any difference in either direction. Adding an entitlement is therefore a visible, reviewable
   diff rather than something that appears only in shipped binaries.

## What signing changes for users

- **Gatekeeper stops refusing the app.** This is the whole point.
- **The Accessibility grant survives updates.** An ad-hoc signature's designated requirement is a
  bare `cdhash`, which changes with every build, so TCC treated each update as a different
  application and quietly dropped the Accessibility permission. That is the bug
  `PermissionManager.resetTCCAndRelaunch()` and the proactive `tccutil reset` work around. A
  Developer ID signature's requirement pins the bundle identifier and the Team ID instead:

  ```
  identifier "com.openclip.OpenClip" and anchor apple generic
    and certificate leaf[subject.OU] = <TEAMID>
  ```

  After one final re-grant on the first signed release, updates stop breaking Accessibility.
- **The Team ID becomes a commitment.** Sparkle checks that an update is signed by the same team
  as the installed app. Changing teams later means installed copies reject every future update and
  every user has to reinstall by hand. The first notarized release is the moment to be sure the
  certificate belongs to the account that will own OpenClip long-term.
- **The first signed release still updates cleanly.** The installed copies are ad-hoc, so Sparkle
  has no team to compare against and validates the Ed25519 appcast signature only. Release notes
  for that version should tell users to re-grant Accessibility once.

## Checking a build by hand

`scripts/verify_signing.sh` runs all of this and fails the build. To reproduce it directly:

```bash
APP=build/DerivedData/Build/Products/Release/OpenClip.app

codesign --verify --deep --strict --verbose=2 "$APP"   # structurally valid
codesign -dvv "$APP"                                   # flags contain "runtime"; Authority=Developer ID
                                                       # Application; Timestamp present; TeamIdentifier set
codesign -d --entitlements - --xml "$APP"              # only the apple-events entitlement
codesign -d -r- "$APP"                                 # designated requirement pins identifier + team
xcrun stapler validate "$APP"                          # "The validate action worked!"
spctl -a -vv -t exec "$APP"                            # accepted, source=Notarized Developer ID
spctl -a -vv -t open --context context:primary-signature build/OpenClip.dmg
```

`spctl` above assesses a file with no quarantine attribute. `verify_signing.sh --require notarized`
repeats the assessment on a quarantined copy, which is the state a download actually arrives in:

```bash
xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" /tmp/OpenClip.app
spctl -a -vv -t exec /tmp/OpenClip.app
```

## Verifying a published download

Independent of signing, release artifacts carry a Sigstore build-provenance attestation binding
them to the tag and workflow run that produced them:

```bash
gh attestation verify OpenClip-v1.4.0.dmg --repo ganeshmshetty/openclip \
    --signer-workflow ganeshmshetty/openclip/.github/workflows/release.yml
```

## Troubleshooting

| Symptom | Cause |
|---|---|
| `AMFIUnserializeXML: syntax error near line N` | An XML comment in the entitlements file. Remove it. |
| `... is still ad-hoc signed while the app is not` | Something was signed outside `sign_artifact.sh`, or a new embedded helper is not covered by `oc_nested_code_items`. |
| `not declared in OpenClip.entitlements: com.apple.security.get-task-allow` | The artifact came straight from `xcodebuild` without the re-sign step. |
| `no secure timestamp` | Signed while offline. The timestamp needs Apple's timestamp server. |
| Notary status `Invalid` | The script prints Apple's log; it names the offending binary and reason. |
| `rejected ... source=Unnotarized Developer ID` | Signed correctly but not notarized yet. |
| `resource fork, Finder information, or similar detritus not allowed` | An extended attribute on the bundle. `com.apple.FinderInfo` is the usual culprit; dmgbuild's `hide_extensions` writes one, which is why `make_dmg.sh` does not use it. Clear with `xattr -cr`. |
| `The staple and validate action failed! Error 65` | No ticket for that exact build. Re-notarize; a ticket is tied to the cdhash. |

## Continuous integration

`.github/workflows/ci.yml` builds **ad-hoc on every push and pull request**, and that is the right
choice rather than a limitation: pull requests from forks get no access to secrets, so a signing
certificate there would only ever work for collaborator branches, and a check that silently does
nothing for outside contributors is worse than one that behaves identically for everyone. An
ad-hoc build still exercises the entire signing path — hardened runtime, real entitlements, and the
inside-out pass over Sparkle's nested helpers — and a dedicated step verifies the app unpacked from
the archive, so the hardening regression that shipped unnoticed for months cannot recur.

`.github/workflows/release.yml` signs, notarizes, and staples when the secrets below are present.

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12` | The Developer ID Application certificate and private key, base64 encoded: `base64 -i Certificates.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | The password set when exporting that .p12 from Keychain Access |
| `NOTARY_KEY_P8` | The full contents of `AuthKey_XXXXXXXXXX.p8`, including the BEGIN and END lines |
| `NOTARY_KEY_ID` | The `XXXXXXXXXX` from that filename |
| `NOTARY_ISSUER_ID` | The issuer UUID from App Store Connect, **Users and Access › Integrations › Team Keys** |

`SPARKLE_ED_PRIVATE_KEY` and `TAP_GITHUB_TOKEN` are separate and already configured.

There is deliberately **no secret for the Team ID or the certificate name**. The workflow imports
the .p12 into a temporary keychain that holds exactly one Developer ID Application identity and
then runs with `OPENCLIP_SIGN_IDENTITY=auto`, which resolves the identity from that keychain and
fails loudly if it finds none or more than one. A Team ID stored separately is a value that can
drift out of step with the certificate it is supposed to describe.

### Behaviour when secrets are missing

All five are required **together**. A certificate without notary credentials would sign
successfully and then fail minutes later at the notarization step, so the workflow checks for the
whole set up front. If any are absent — a fork, or secrets rotated away — the release still builds
and publishes, ad-hoc signed, with a `::warning::` naming exactly which secrets were missing.

This keeps tagging working under any configuration, but the degradation is real: **an ad-hoc
release is refused by Gatekeeper on every Mac except the one that built it, and must not be
published as a real release.** Check the run's warnings before announcing a version.

### How the certificate is handled

Plain `security` commands, no third-party action — the same reasoning that pins the Sparkle
download by SHA-256 applies to anything that handles OpenClip's signing key. The keychain is
created under `RUNNER_TEMP`, is never made the default keychain, is only prepended to the user
search list, and is deleted by a step marked `if: always()` so a failed or cancelled run takes the
private key with it. The .p8 is passed to `notarize_artifact.sh` as inline PEM text through the
environment and never written into the workspace.
