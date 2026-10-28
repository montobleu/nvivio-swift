# Nvivio for iOS

Cookieless, privacy-first analytics for your native app: screen views, time on a screen and
custom events, sent to [Nvivio](https://nvivio.com). The SDK stores nothing on the device and
uses no identifiers, so your app needs no consent prompt for it where your website needs no
cookie banner.

iOS 15+, macOS 12+, tvOS 15+, visionOS 1+. Swift 6, no dependencies.

## Install

With Swift Package Manager: in Xcode, File › Add Package Dependencies…, enter
`https://github.com/montobleu/nvivio-swift` and add the `Nvivio` library to your app target. In
a `Package.swift`:

```swift
.package(url: "https://github.com/montobleu/nvivio-swift", from: "1.0.0")
```

and depend on the product `Nvivio`.

Then list your app's bundle ID in Nvivio: Settings › Parts › + App. Requests from a
bundle ID that is not listed are refused.

## Start

Once, as early as possible (your `App`'s `init` or `application(_:didFinishLaunchingWithOptions:)`):

```swift
import Nvivio

Nvivio.start(site: "NV-6T78AE8")
```

Calls made before `start` wait in memory and are sent once it is called.

## Screens

```swift
Nvivio.screen("Checkout")                  // UIKit: in viewDidAppear
SomeView().nvivioScreen("Checkout")        // SwiftUI: on appear
```

Calling it again for the screen that is already current sends nothing, so redraws are safe.
When the next screen shows or the app goes to the background, the SDK sends how long the
screen was in the foreground. There are no automatic screens: you name them.

## Events

```swift
Nvivio.event("Purchase", ["plan": "pro", "qty": 2, "gift": true])
Nvivio.event("Signup", ["plan": "\(plan)", "seats": .int(seats)])   // from variables
```

An event belongs to the current screen, so call `screen` first. Names: letters, digits, spaces
and `_ . : -`, at most 64 characters (`pv`, `en`, `pageview`, `engagement` and `ln` are
reserved). Up to 20 properties; keys `[A-Za-z0-9_.-]`, at most 40 characters; values text (at
most 200 characters), number or boolean.

## Deep links

Pass the URL that opened the app; its `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`
and `utm_content` go with the next screen view:

```swift
.onOpenURL { url in Nvivio.open(url) }
```

## Opting out

```swift
Nvivio.isEnabled = false
```

What waits is dropped and nothing is sent until it is `true` again. The SDK does not remember
this: keep the user's choice in your app's settings and set `isEnabled` at launch.

## Debugging

```swift
Nvivio.debug = true
```

logs every request and answer (subsystem `com.nvivio`, category `Nvivio`). Without it, a setup
error (unknown site, app not listed) is logged once per launch, with what to do about it.

## What it sends

Every 10 seconds, at once when 20 events wait, and when the app goes to the background, one
HTTPS request to `https://nviv.io/a` with:

- the site code, your bundle ID and `CFBundleShortVersionString`;
- the OS and its version ("iOS 26.1"), phone, tablet or desktop, the screen's width in points,
  the user's first preferred language and the model code ("iPhone14,5", read with `uname`);
- a random launch code, made in memory when the app starts and gone when it stops;
- the events: screen names, time on a screen, your custom events and their properties.

No IDFA, IDFV or any other identifier; no cookies, no cache, nothing written to disk. The model
code is there to show which phones people use (Nvivio names it, "iPhone 13", and reports a model
only once it has five visitors); it is never part of how Nvivio counts visitors, so it cannot
be used to recognise a device. Events wait in memory only (at most 200; older than an hour they are dropped). After a
network error or a busy server the SDK tries again later (10 s, 30 s, 60 s… up to 5 minutes).
Nvivio derives the country, region and city from the IP address and does not keep the address.

The full protocol is in [`PROTOCOL.md`](PROTOCOL.md).

## Privacy manifest and App Store label

The package ships `PrivacyInfo.xcprivacy`: no tracking, no tracking domains, none of Apple's
required-reason APIs (`uname` is not one), and three collected data types, not linked to the user
and not used for tracking, for analytics. Xcode adds it to your app's privacy report.

In App Store Connect, App Privacy, declare:

- **Data Not Linked to You**: Usage Data › Product Interaction, Location › Coarse Location and
  Diagnostics › Other Diagnostic Data (the app's version, the OS version and the device model);
  purpose Analytics; not used to track.

## Example

`Example/NvivioExample.xcodeproj` is a small SwiftUI app with three screens, a custom event and
a deep link (`nvivioexample://products?utm_source=newsletter`). It sends to a local ingest at
`http://localhost:8797/a`.

```sh
swift test                      # the SDK's tests
open Example/NvivioExample.xcodeproj
```
