import Foundation
import Testing
@testable import Nvivio

@Suite struct Payload {
    @Test func carriesTheDeviceTheLaunchAndEveryEventField() {
        let h = Harness()
        h.tracker.screen("Checkout")
        h.advance(4)
        h.tracker.event("Purchase", ["plan": "pro", "qty": 2, "price": 9.5, "gift": true])
        h.advance(6)

        let batch = try! #require(h.batches.first)
        #expect(h.batches.count == 1)
        #expect(batch.s == "NV-6T78AE8")
        #expect(batch.a == "com.acme.shop")
        #expect(batch.v == "2.3.1")
        #expect(batch.o == "iOS 26.1")
        #expect(batch.m == "phone")
        #expect(batch.w == 402)
        #expect(batch.l == "nl-BE")
        #expect(batch.h == "iPhone14,5")
        #expect(isCode(batch.k, length: 16))

        let (view, purchase) = (batch.e[0], batch.e[1])
        #expect(batch.e.count == 2)
        #expect(view.n == "pv" && view.u == "Checkout" && view.g == 10)
        #expect(isCode(view.i, length: 8))
        #expect(view.p == nil && view.d == nil && view.q == nil)
        #expect(purchase.n == "Purchase" && purchase.u == "Checkout" && purchase.i == view.i && purchase.g == 6)
        #expect(purchase.p == ["plan": .string("pro"), "qty": .int(2), "price": .double(9.5), "gift": .bool(true)])
    }

    @Test func keepsOneLaunchIdAndANewViewIdPerScreen() {
        let h = Harness()
        h.tracker.screen("Home")
        h.advance(10)
        h.answer(Harness.delivered)
        h.tracker.screen("Products")
        h.advance(10)

        let batches = h.batches
        #expect(batches.count == 2)
        #expect(batches[0].k == batches[1].k)
        #expect(batches[0].e[0].i != batches[1].e.last!.i)
    }

    @Test func sendsTheOldestTwentyAtOnceAndTheRestAfterTenSeconds() {
        let h = Harness()
        h.tracker.screen("Home")
        for n in 1...24 { h.tracker.event("Tap \(n)") }
        h.settle()

        #expect(h.batches.count == 1)
        #expect(h.batches[0].e.map(\.n) == ["pv"] + (1...19).map { "Tap \($0)" })
        h.answer(Harness.delivered)
        h.advance(9)
        #expect(h.batches.count == 1)
        h.advance(1)
        #expect(h.batches.count == 2)
        #expect(h.batches[1].e.map(\.n) == (20...24).map { "Tap \($0)" })
    }

    @Test func countsTheAgeWhenTheRequestLeaves() {
        let h = Harness()
        h.tracker.screen("Home")
        h.advance(10)
        #expect(h.batches[0].e[0].g == 10)
        h.answer(.unreachable("offline"))
        h.advance(10)
        #expect(h.batches[1].e[0].g == 20)
    }

    @Test func keepsCallsFromBeforeStartButDropsEventsOlderThanAnHour() {
        let h = Harness(started: false)
        h.tracker.screen("Home")
        h.advance(3595)
        h.tracker.screen("Cart")
        h.advance(60)
        #expect(h.batches.isEmpty)

        h.start()
        h.advance(10)
        // Home's screen view is 3665 s old by now; its time on screen and the next screen view are not.
        let events = h.batches[0].e
        #expect(events.map(\.n) == ["en", "pv"])
        #expect(events[0].d == 3595 && events[0].g == 70)
        #expect(events[1].u == "Cart" && events[1].g == 70)
    }

    @Test func leavesOutWhatTheServerWouldRefuse() {
        let h = Harness()
        h.tracker.event("Early")  // no screen yet
        h.tracker.screen("Home")
        for name in ["", "pv", "en", "ln", "pageview", "engagement", "Café", String(repeating: "x", count: 65)] {
            h.tracker.event(name)
        }
        // Sorted by key: a_long, a_nan, bad key, k10…k34; the first 20 valid ones stay.
        var many: [String: NvivioValue] = ["a_long": .string(String(repeating: "a", count: 250)), "a_nan": .double(.nan), "bad key": 1]
        for n in 10..<35 { many["k\(n)"] = .int(n) }
        h.tracker.event("Many", many)
        h.advance(10)

        let events = h.batches[0].e
        #expect(events.map(\.n) == ["pv", "Many"])
        let props = events[1].p ?? [:]
        #expect(props.count == 20)
        #expect(props["a_long"] == .string(String(repeating: "a", count: 200)))
        #expect(props["a_nan"] == nil && props["bad key"] == nil)
        #expect(props["k10"] == .int(10) && props["k28"] == .int(28) && props["k29"] == nil)
    }
}

@Suite struct Screens {
    @Test func sendsTheTimeOnAScreenBeforeTheNextScreenView() {
        let h = Harness()
        h.tracker.screen("Home")
        h.advance(5.4)
        h.tracker.screen("Products")
        h.advance(10)

        let events = h.batches[0].e
        #expect(events.map(\.n) == ["pv", "en", "pv"])
        #expect(events[1].i == events[0].i && events[1].d == 5 && events[1].u == nil)
        #expect(events[2].u == "Products" && events[2].i != events[0].i)
    }

    @Test func leavesOutLessThanASecond() {
        let h = Harness()
        h.tracker.screen("Home")
        h.advance(0.6)
        h.tracker.screen("Products")
        h.advance(10)
        #expect(h.batches[0].e.map(\.n) == ["pv", "pv"])
    }

    @Test func sendsNothingForTheScreenThatIsAlreadyCurrent() {
        let h = Harness()
        h.tracker.screen("Home")
        h.advance(3)
        h.tracker.screen("Home")
        h.tracker.screen(" Home ")
        h.advance(10)
        #expect(h.batches[0].e.map(\.n) == ["pv"])
    }

    @Test func sendsTheTimeOnScreenAtOnceInTheBackground() {
        let h = Harness()
        let done = Locked(false)
        h.tracker.screen("Home")
        h.advance(7)
        h.tracker.enterBackground { done.value = true }
        h.settle()

        #expect(h.batches.count == 1)
        #expect(h.batches[0].e.map(\.n) == ["pv", "en"])
        #expect(h.batches[0].e[1].d == 7)
        #expect(!done.value)
        h.answer(Harness.delivered)
        #expect(done.value)
    }

    @Test func countsForegroundTimeOnlyAndNoNewScreenViewWhenBack() {
        let h = Harness()
        h.tracker.screen("Home")
        h.advance(3)
        h.tracker.enterBackground {}
        h.answer(Harness.delivered)
        h.advance(100)
        h.tracker.enterForeground()
        h.advance(4)
        h.tracker.enterBackground {}
        h.settle()

        let batches = h.batches
        #expect(batches.count == 2)
        #expect(batches[1].e.map(\.n) == ["en"])
        #expect(batches[1].e[0].d == 4 && batches[1].e[0].i == batches[0].e[0].i)
    }

    @Test func putsTheDeepLinksCampaignOnTheNextScreenViewOnly() {
        let h = Harness()
        h.tracker.open(URL(string: "acme://promo?utm_source=newsletter&utm_campaign=spring&utm_medium=&ref=x")!)
        h.tracker.screen("Promo")
        h.tracker.screen("Home")
        h.advance(10)

        let events = h.batches[0].e
        #expect(events[0].q == ["utm_source": "newsletter", "utm_campaign": "spring"])
        #expect(events[1].q == nil)
    }
}

@Suite struct Answers {
    @Test func doneAfter204() {
        let h = Harness()
        h.tracker.screen("Home")
        h.advance(10)
        h.answer(Harness.delivered)
        h.advance(600)
        #expect(h.batches.count == 1)
    }

    @Test(arguments: [400, 403, 404])
    func dropsTheBatchOnASetupErrorAndNeverRetries(status: Int) {
        let h = Harness()
        h.tracker.screen("Home")
        h.advance(10)
        h.answer(.status(status, Data(#"{"error":"App hoort niet bij deze site.","fix":"Voeg de bundle ID toe."}"#.utf8)))
        h.advance(600)
        #expect(h.batches.count == 1)

        h.tracker.screen("Products")
        h.advance(10)
        #expect(h.batches.count == 2)
        #expect(h.batches[1].e.map(\.n) == ["en", "pv"])
    }

    @Test(arguments: [Reply.unreachable("offline"), .status(429, Data()), .status(500, Data()), .status(503, Data()), .status(302, Data())])
    func keepsTheEventsAndRetriesWithBackoff(failure: Reply) {
        let h = Harness()
        h.tracker.screen("Home")
        h.advance(10)
        h.answer(failure)
        // While backing off, not even 20 waiting events leave.
        for n in 1...20 { h.tracker.event("Tap \(n)") }
        h.advance(9)
        #expect(h.batches.count == 1)
        h.advance(1)
        #expect(h.batches.count == 2)
        #expect(h.batches[1].e.first?.n == "pv" && h.batches[1].e.count == 20)

        for wait in [30, 60, 120, 240, 300, 300] {
            h.answer(failure)
            let before = h.batches.count
            h.advance(TimeInterval(wait - 1))
            #expect(h.batches.count == before)
            h.advance(1)
            #expect(h.batches.count == before + 1)
        }

        h.answer(Harness.delivered)
        h.advance(10)
        #expect(h.batches.last?.e.map(\.n) == ["Tap 20"])
    }

    @Test func keepsAtMostTwoHundredDroppingTheOldest() {
        let h = Harness(started: false)
        h.tracker.screen("Home")
        for n in 1...210 { h.tracker.event("E\(n)") }
        h.start()
        while h.transport.unanswered > 0 { h.answer(Harness.delivered) }

        let names = h.batches.flatMap { $0.e.map(\.n) }
        #expect(names.count == 200)
        #expect(names.first == "E11" && names.last == "E210")
    }

    @Test func retriedEventsCountTowardsTheCap() {
        let h = Harness()
        h.tracker.screen("Home")
        for n in 1...19 { h.tracker.event("E\(n)") }
        h.settle()
        #expect(h.batches[0].e.count == 20)
        for n in 20...209 { h.tracker.event("E\(n)") }
        h.answer(.unreachable("offline"))
        h.advance(10)
        while h.transport.unanswered > 0 { h.answer(Harness.delivered) }

        let names = h.batches.dropFirst().flatMap { $0.e.map(\.n) }
        #expect(names.count == 200)
        #expect(names.first == "E10" && names.last == "E209")
    }
}

@Suite struct OptingOut {
    @Test func dropsWhatWaitsAndSendsNothingUntilBackOn() {
        let h = Harness()
        h.tracker.screen("Home")
        h.tracker.event("Tap")
        h.tracker.isEnabled = false
        h.tracker.screen("Settings")
        h.tracker.event("Tap")
        h.tracker.open(URL(string: "acme://x?utm_source=mail")!)
        h.tracker.enterBackground {}
        h.advance(600)
        #expect(!h.tracker.isEnabled)
        #expect(h.batches.isEmpty)

        h.tracker.isEnabled = true
        h.tracker.enterForeground()
        h.tracker.screen("Settings")
        h.advance(10)
        #expect(h.batches.count == 1)
        #expect(h.batches[0].e.map(\.n) == ["pv"])
        #expect(h.batches[0].e[0].u == "Settings" && h.batches[0].e[0].q == nil)
    }
}

@Suite struct Request {
    @Test func postsJSONWithTheSDKsUserAgent() {
        let request = URLSessionTransport.request(Data("{}".utf8), to: Nvivio.defaultEndpoint)
        #expect(request.url?.absoluteString == "https://nviv.io/a")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Nvivio-iOS/1.0.0")
    }

    @Test func takesValuesFromLiterals() throws {
        let plan = "team"
        let props: [String: NvivioValue] = ["plan": "pro", "label": "\(plan)", "qty": 2, "price": 9.5, "gift": false]
        #expect(props == ["plan": .string("pro"), "label": .string("team"), "qty": .int(2), "price": .double(9.5), "gift": .bool(false)])
        let json = String(decoding: try JSONEncoder().encode(["qty": props["qty"]!]), as: UTF8.self)
        #expect(json == #"{"qty":2}"#)
    }
}

@Suite struct PrivacyManifest {
    @Test func declaresNoTrackingAndOnlyUnlinkedAnalyticsData() throws {
        let url = try #require(Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect((plist["NSPrivacyAccessedAPITypes"] as? [Any])?.isEmpty == true)
        let types = try #require(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        #expect(Set(types.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
            == ["NSPrivacyCollectedDataTypeProductInteraction", "NSPrivacyCollectedDataTypeCoarseLocation", "NSPrivacyCollectedDataTypeOtherDiagnosticData"])
        for type in types {
            #expect(type["NSPrivacyCollectedDataTypeLinked"] as? Bool == false)
            #expect(type["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
            #expect(type["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAnalytics"])
        }
    }
}
