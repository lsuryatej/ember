import Foundation
import CryptoKit

/// Turns on phone alerts for `engine` and tells `other` about it.
private func enablePhone(_ engine: Engine, telling other: Engine, at now: Date) -> String {
    var settings = engine.state.settings
    settings.phoneAlertsOn = true
    settings.phoneTopic = PairSecret.newTopic(prefix: "ember-phone-")
    _ = deliver(engine.updateSettings(settings, at: now), to: other, at: now)
    return settings.phoneTopic!
}

private func phonePushes(_ effects: [Effect]) -> [String] {
    effects.compactMap { if case .phonePush(let topic) = $0 { return topic } else { return nil } }
}

func runFeatureTests() {
    suite("iPhone heads-up when their Mac is away") {
        let (a, b) = makePair()
        let t = at(2026, 11, 20, 21)
        let topic = enablePhone(b, telling: a, at: t)

        equal(phonePushes(try! a.send(.spicy, at: t)), [], "not while they're at their Mac")

        _ = deliver(b.setAway(true, at: t.addingTimeInterval(10)), to: a, at: t.addingTimeInterval(10))
        equal(phonePushes(try! a.send(.spicy, at: t.addingTimeInterval(70))), [topic], "their phone gets nudged once their Mac is away")
        check(a.phoneFallbackTopic(at: t.addingTimeInterval(70)) != nil, "and the menu can say so before you send")

        _ = deliver(b.setBusy(until: t.addingTimeInterval(3600), at: t.addingTimeInterval(80)), to: a, at: t.addingTimeInterval(80))
        equal(phonePushes(try! a.send(.spicy, at: t.addingTimeInterval(140))), [], "not while they're busy")
        _ = deliver(b.setBusy(until: nil, at: t.addingTimeInterval(150)), to: a, at: t.addingTimeInterval(150))

        var quiet = b.state.settings
        quiet.quietHoursOn = true
        _ = deliver(b.updateSettings(quiet, at: t.addingTimeInterval(160)), to: a, at: t.addingTimeInterval(160))
        let night = at(2026, 11, 21, 3)
        equal(phonePushes(try! a.send(.spicy, at: night)), [], "not in their quiet hours")

        var off = b.state.settings
        off.phoneAlertsOn = false
        _ = deliver(b.updateSettings(off, at: night.addingTimeInterval(10)), to: a, at: night.addingTimeInterval(10))
        equal(a.state.partner?.phoneTopic, nil, "switching alerts off stops sharing the topic")
        equal(b.state.settings.phoneTopic, topic, "but keeps it, so turning it back on needs no new subscription")
    }

    suite("Tell me when they're back") {
        let (a, b) = makePair()
        let t = at(2026, 11, 22, 18)
        a.setWatchForReturn(true)
        equal(a.state.watchForReturn, false, "can't be armed while they're already there")

        _ = deliver(b.setAway(true, at: t), to: a, at: t)
        a.setWatchForReturn(true)
        check(a.state.watchForReturn, "armed while they're away")
        let back = deliver(b.setAway(false, at: t.addingTimeInterval(1200)), to: a, at: t.addingTimeInterval(1201))
        equal(alerts(back).first?.body, "Back at their Mac. Good moment for a ping?", "fires when they unlock")
        equal(alerts(back).first?.sound, "Ping", "with a sound")
        equal(a.state.watchForReturn, false, "and disarms")

        _ = deliver(b.setAway(true, at: t.addingTimeInterval(1300)), to: a, at: t.addingTimeInterval(1300))
        equal(alerts(deliver(b.setAway(false, at: t.addingTimeInterval(1400)), to: a, at: t.addingTimeInterval(1400))).count, 0, "once, not every time")

        _ = deliver(b.setAway(true, at: t.addingTimeInterval(1500)), to: a, at: t.addingTimeInterval(1500))
        a.setWatchForReturn(true)
        let late = deliver(b.setAway(false, at: t.addingTimeInterval(1600)), to: a, at: t.addingTimeInterval(1600 + 3600))
        check(alerts(late).first?.body.hasPrefix("Was back at their Mac at") == true, "news arriving late says when")
        equal(alerts(late).first?.sound, nil, "and stays quiet")
    }

    suite("Version handshake") {
        let (a, b) = makePair()
        b.appVersion = "9.9.9"
        let t = at(2026, 11, 23)
        let snapshot = b.snapshot(at: t)
        equal(snapshot.protocolVersion, Wire.protocolVersion, "snapshots carry the protocol version")
        equal(snapshot.appVersion, "9.9.9", "and the app version")
        _ = deliver(b.hello(at: t), to: a, at: t)
        equal(a.versionGap, nil, "same protocol, no warning")

        var newer = snapshot
        newer.protocolVersion = Wire.protocolVersion + 1
        _ = a.receive(Envelope(id: UUID(), from: UUID(), sentAt: t.addingTimeInterval(1), payload: .snapshot(newer, wantsReply: false)), at: t.addingTimeInterval(1))
        equal(a.versionGap, .theirsIsNewer("9.9.9"), "a newer build on their side is spotted")

        var older = snapshot
        older.protocolVersion = nil
        _ = a.receive(Envelope(id: UUID(), from: UUID(), sentAt: t.addingTimeInterval(2), payload: .snapshot(older, wantsReply: false)), at: t.addingTimeInterval(2))
        let expected: Engine.VersionGap? = Wire.protocolVersion > 1 ? .theirsIsOlder("9.9.9") : nil
        equal(a.versionGap, expected, "a build from before the handshake counts as version 1")
    }

    suite("Compatible with the build you already have") {
        // The 0.1.0 Snapshot, field for field.
        struct OldSnapshot: Codable, Equatable {
            var name: String
            var busyUntil: Date?
            var away: Bool
            var presenceAt: Date
            var quietHours: QuietHours?
            var visit: VisitState
        }
        let old = OldSnapshot(name: "Sam", busyUntil: nil, away: true, presenceAt: Date(timeIntervalSince1970: 1_800_000_000), quietHours: .default, visit: .empty)
        let fromOld = try? Wire.decoder().decode(Snapshot.self, from: Wire.encoder().encode(old))
        equal(fromOld?.name, "Sam", "a snapshot from 0.1.0 decodes")
        equal(fromOld?.phoneTopic, nil, "with the new fields empty")

        var new = Snapshot(name: "Alex", busyUntil: nil, away: false, presenceAt: Date(timeIntervalSince1970: 1_800_000_000), quietHours: nil, visit: .empty)
        new.phoneTopic = "ember-phone-x"
        new.protocolVersion = Wire.protocolVersion
        new.appVersion = "0.2.0"
        equal((try? Wire.decoder().decode(OldSnapshot.self, from: Wire.encoder().encode(new)))?.name, "Alex", "and 0.1.0 can read one from this build")

        let settings = try? JSONDecoder().decode(Settings.self, from: Data(#"{"myName":"Alex"}"#.utf8))
        equal(settings?.phoneAlertsOn, false, "phone alerts start off after an update")
    }

    suite("A message from a newer build is told apart from junk") {
        let secret = PairSecret.generate()
        let future = Data(#"{"payload":{"somethingNew":{}}}"#.utf8)
        let box = try! ChaChaPoly.seal(future, using: SymmetricKey(data: secret.key), authenticating: Data(secret.topic.utf8))
        let sealed = box.combined.base64EncodedString()
        equal(try? secret.openData(sealed), future, "it decrypts, so it's from the pair")
        check((try? secret.open(sealed)) == nil, "but doesn't decode, so it's from a newer build")
        check((try? secret.openData("junk")) == nil, "while junk doesn't even decrypt")
    }
}
