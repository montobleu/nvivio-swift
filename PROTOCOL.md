# Nvivio app protocol

What Nvivio's SDKs for native apps send, and the rules every SDK follows (Swift in `sdks/swift`,
Android in `sdks/android`, later React Native and Flutter). The server side is
`packages/shared/src/app.ts` (parsing) and `apps/ingest/src/app.ts` (the endpoint); both are the
reference when this page and the code disagree.

## Privacy rules (not negotiable)

- **Nothing is stored on the device.** No files, no `UserDefaults` / `SharedPreferences`, no
  Keychain, no databases, no cookies or HTTP cache (`URLSessionConfiguration.ephemeral`;
  `HttpURLConnection` with `useCaches = false`). Queued events live in memory and are gone when
  the process ends.
- **No identifiers.** No IDFA, GAID, IDFV, App Set ID, Android ID, serial numbers, push tokens or
  user IDs. The device model (`h`) is no identifier: many people share it, the server never uses
  it to tell visitors apart, and reports fold rare models together. The only codes the SDK makes are random and in memory: the launch id
  (`k`) and screen view ids (`i`).
- **No fingerprinting signals.** iOS: none of Apple's "required reason" APIs (no `UserDefaults`,
  no `systemUptime` / `mach_absolute_time` / `clock_gettime(CLOCK_UPTIME_RAW)`, no file timestamps,
  no disk space, no `activeInputModes`); time comes from `Date()`. Android: nothing beyond the
  public `Build.VERSION.RELEASE`, the screen's configuration and the locale.
- **Opting out** is `isEnabled = false`: the queue is dropped and nothing is sent until it is set
  back. The SDK does not remember it; the app keeps the user's choice in its own settings.

## Request

```
POST https://nviv.io/a
Content-Type: application/json
User-Agent: Nvivio-iOS/1.0.0          (Nvivio-Android/1.0.0, Nvivio-ReactNative/…, Nvivio-Flutter/…)
```

The user agent must start with `Nvivio-<Platform>/<version>`: Android's own HTTP clients
(`okhttp/…`, `Dalvik/…`) are taken for bots otherwise.

```json
{
  "s": "NV-6T78AE8",
  "a": "com.acme.shop",
  "v": "2.3.1",
  "o": "iOS 26.1",
  "m": "phone",
  "w": 402,
  "l": "nl-BE",
  "h": "iPhone14,5",
  "k": "q7m2x9c4h1v8b3n5",
  "e": [
    { "n": "pv", "u": "Checkout", "i": "k2j9x1p4", "g": 4, "q": { "utm_source": "newsletter" } },
    { "n": "Purchase", "u": "Checkout", "i": "k2j9x1p4", "p": { "plan": "pro" }, "g": 1 },
    { "n": "en", "i": "k2j9x1p4", "d": 37 }
  ]
}
```

| Field | What | Source |
|---|---|---|
| `s` | The site's code, as in the web script | `start(site:)` |
| `a` | Bundle ID (iOS) or package name (Android); must be listed in the site's app (Settings › Onderdelen) | `Bundle.main.bundleIdentifier`, `context.packageName` |
| `v` | App version, up to 32 characters | `CFBundleShortVersionString`, `versionName` |
| `o` | Platform and OS version | `"\(systemName) \(systemVersion)"` (iOS, iPadOS), `"Android \(Build.VERSION.RELEASE)"` |
| `m` | `phone`, `tablet` or `desktop` | iOS: idiom `.pad` is tablet, `.mac` is desktop. Android: `smallestScreenWidthDp >= 600` is tablet |
| `w` | Screen width in points or dp, the shorter side | `min(width, height)` |
| `l` | The user's first language, BCP 47 | `Locale.preferredLanguages.first`, `LocaleList.getDefault()[0].toLanguageTag()` |
| `h` | Hardware, the device model: iOS its code, Android the maker and model with a vertical bar between them. Only to show which phones people use: never in the visitor's hash, and a report shows a model only from five visitors | `uname` `machine` ("iPhone14,5"; `SIMULATOR_MODEL_IDENTIFIER` in the Simulator), `Build.MANUFACTURER` and `Build.MODEL` ("samsung\|SM-S921B") |
| `k` | Launch id: 16 random characters `[a-z0-9]`, made once when the process starts, memory only | random |
| `e` | 1 to 20 events, oldest first | |

Per event:

| Field | What |
|---|---|
| `n` | `pv` (screen view), `en` (time on a screen) or a custom event name: ASCII letters, digits, spaces and `_ . : -`, at most 64 characters. `pageview`, `engagement` and `ln` are reserved. |
| `u` | The screen ("Checkout", "Settings/Privacy"), at most 300 characters. Required for `pv` and custom events; custom events carry the screen they happen on. |
| `i` | The screen view's id: 8 random characters `[a-z0-9]`, new for every `pv`; `en` and custom events carry the id of the screen they belong to. |
| `p` | Custom events: up to 20 properties, keys `[A-Za-z0-9_.-]{1,40}`, values string (at most 200 characters), number or boolean. |
| `d` | `en` only: whole seconds the screen was in the foreground. |
| `g` | Whole seconds since the event happened (0 to 3600). The SDK drops events older than an hour. |
| `q` | `pv` only: the `utm_source`, `utm_medium`, `utm_campaign`, `utm_term` and `utm_content` of the deep link that opened the app (`open(url)`), on the first screen view after it. |

## Behaviour

- **Screens**: `screen(name)` sends `pv` with a new view id. Calling it again for the screen that is
  already current (SwiftUI redraws, `onAppear` twice) sends nothing.
- **Time on a screen**: when the next screen is shown, and when the app goes to the background,
  the SDK first sends `en` for the current screen with the seconds it was in the foreground since
  it was shown or since the app came back (only when that is 1 second or more). Back in the
  foreground the screen counts on; no new `pv`.
- **Batching**: events wait in memory; a request leaves when 20 are waiting, 10 seconds after the
  first one waits, and at once when the app goes to the background (iOS:
  `beginBackgroundTask`; Android: on the SDK's own background thread).
- **Answers**: `204` is done. `400`, `403` and `404` are a setup error (unknown site, app not
  listed, invalid event): drop the batch, never retry, and log the server's `error` and `fix`
  once (`debug`, and once per launch without it). A network error, `429`, `5xx` or any other
  answer (a Wi-Fi login page that redirects): keep the events and try again with the next send
  (backing off: 10 s, 30 s, 60 s, 120 s, 240 s, then every 5 minutes).
  At most 200 events wait in memory; beyond that the oldest go first. `g` is computed when a
  request leaves, so a retried event keeps its real age.
- **Threads**: every public call is cheap and safe from any thread; the work happens on the SDK's
  own serial queue or thread. Never on the main thread.
- **No automatic screens by default.** Android may name screens after activities when the app
  asks for it (`trackActivities = true`); iOS has no swizzling.
- **Debug**: `debug = true` logs every request and answer (os `Logger`, `android.util.Log`, tag
  `Nvivio`).
- **Endpoint**: `https://nviv.io/a`, replaceable for tests and local development.
