# Native content requirements

The native content contract is introduced in the 1.9.0 source version. Catalog packages using it must declare `minOpenClipVersion: "1.9.0"` and be published alongside that release; older apps ignore unknown requirement keys.

```json
"requirements": {
  "content": ["url", "email"]
}
```

`content` is a non-empty array of `url`, `email`, `date`, `path`, `phone`, or `address`. At least one occurrence of **any** listed type enables the content gate. Input, paste target, app restrictions, and regex requirements must also pass. A malformed legacy regex retains its previous fail-open behavior for that gate, but cannot bypass a content requirement. Unknown content types, empty arrays, nulls, and wrong shapes reject the manifest, including nested group actions.

Declaring native content makes an action contextual, just as a regex does. User exclusions from contextual actions still apply. Required options are checked when invoked and open configuration rather than hiding the action.

## Detection and JavaScript input

Recognition scans the entire selection, including items embedded in prose. Results are ordered by occurrence, preserve repeated values, and are cached lazily per requested type on the immutable selection snapshot. Copies carrying new cursor or editability evidence share that cache. URLs and emails share one link scan. Visibility and JavaScript execution use the same cache; execution never scans different input or truncates to the regex-matched substring.

`openclip.input.text` keeps the original selection. `openclip.input.detected` always has six deeply frozen arrays; unrequested types and requested types without matches have empty arrays. Without a content requirement all six arrays are empty.

| Requirement | JavaScript property | Values |
| --- | --- | --- |
| `url` | `urls` | Normalized HTTP/HTTPS URL strings. Bare web domains use HTTPS; localhost/IP endpoint fallbacks use HTTP. Non-web schemes are excluded. |
| `email` | `emails` | Detected email address strings, with a detected `mailto:` prefix removed. |
| `phone` | `phones` | Native detector phone number strings; formatting is preserved by the native detector. |
| `path` | `paths` | Absolute path strings; expands `~/`, decodes `file://` URLs, handles quoted or shell-escaped spaces, and removes compiler line/column suffixes and surrounding punctuation. |
| `date` | `dates` | Objects: `{ text, date, duration, timeZone? }`. `date` is an ISO-8601 UTC string, `duration` is seconds, and `timeZone` is the detected zone identifier when available. |
| `address` | `addresses` | Objects: `{ text, components }`. Available components use `name`, `jobTitle`, `organization`, `street`, `city`, `state`, `postalCode`, `country`, and `phone`; absent fields are omitted. |

Paths are recognized lexically, without filesystem probes. A path result does **not** promise that a file exists; the builtin Reveal in Finder action separately checks existence, keeping its bounded filesystem probes. Quote paths containing spaces when embedded in prose. Native date/phone/address recognition depends on the system detector's supported language and regional formats. Relative dates resolve when first detected for the snapshot.

The builtin Open Link action uses the same URL detector and continues opening the first URL. Add Event uses the shared date detector and its existing first-date behavior. Reveal in Finder uses the shared path scanner and its existing existence checks.

```javascript
function action() {
  const urls = [...new Set(openclip.input.detected.urls)];
  for (const url of urls) openclip.openURL(url);
}
```

Each call appends an effect, executed in call order by the existing sequence mechanism. For extensions declaring URL content, HTTP/HTTPS effects use the source browser if it is recognized; otherwise they use the default browser. Other JS extensions retain their existing URL-opening behavior. Effects such as `mailto:` or `tel:` still use their registered system handler.

The official Open Links package lives in the separate extension catalog at `raw/OpenLinks.openclipext`. It deduplicates normalized URLs and opens them in first occurrence order.

## Retiring expressions

`requirements.expression` and its custom evaluator have been removed. A manifest declaring that field is rejected with an error identifying the retired field and suggesting content or regex requirements; it is never silently enabled by dropping the expression. The catalog inventory at implementation time contained no manifest using the retired field.

Migrate `isURL(text)` or `isEmail(text)` according to the intended behavior: `content` detects occurrences anywhere in the selection, whereas an anchored regex can require whole-input matching. Replace app restrictions with `apps`/`appsMode`, nonblank input with `input: "text"`, and custom string/length conditions with an appropriate regex. Complex expressions need manual review; there is no automatic rewrite that changes their semantics.

Colors and JSON parsing are deferred. Unknown future type names are rejected until their native contracts are implemented.
