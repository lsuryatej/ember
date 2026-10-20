import AppKit
import SwiftUI

// Renders the real menu in realistic states, light and dark, to PNGs.
// The states are made by driving two real engines against each other, the
// way the tests do, then loading the result into a real AppModel that never
// connects. CI publishes the images to the `screenshots` branch.
//
//   EmberScreenshots <output directory>

setvbuf(stdout, nil, _IOLBF, 0)

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "screenshots")
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ember-shots-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

let now = Date()
let minute: TimeInterval = 60
let day: TimeInterval = 24 * 3600

func deliver(_ effects: [Effect], to engine: Engine, at time: Date) -> [Effect] {
    effects.compactMap { if case .publish(let envelope) = $0 { return envelope } else { return nil } }
        .flatMap { engine.receive($0, at: time) }
}

/// Alex's Mac, paired with Sam's, after `story` has played out between them.
func paired(_ story: (_ alex: Engine, _ sam: Engine) -> Void) -> Store {
    var alexState = EngineState()
    alexState.settings.myName = "Alex"
    alexState.settings.quietHoursOn = false
    alexState.settings.partnerHandle = "sam@example.com"
    var samState = EngineState()
    samState.settings.myName = "Sam"
    samState.settings.quietHoursOn = false
    let alex = Engine(state: alexState, deviceID: UUID())
    let sam = Engine(state: samState, deviceID: UUID())
    let start = now.addingTimeInterval(-2 * day)
    _ = deliver(deliver(alex.hello(at: start), to: sam, at: start), to: alex, at: start)
    story(alex, sam)

    var store = Store()
    store.deviceID = alex.deviceID
    store.pair = PairSecret.generate()
    store.engine = alex.state
    return store
}

/// A believable evening: a 💛 this afternoon, a match earlier, and a fresh
/// ping from Sam waiting for an answer.
func evening(_ alex: Engine, _ sam: Engine) {
    let afternoon = now.addingTimeInterval(-5 * 3600)
    _ = deliver(deliver(try! alex.send(.missYou, at: afternoon), to: sam, at: afternoon), to: alex, at: afternoon)
    let earlier = now.addingTimeInterval(-70 * minute)
    _ = deliver(try! sam.send(.spicy, at: earlier), to: alex, at: earlier)
    _ = deliver(deliver(try! alex.send(.spicier, at: earlier.addingTimeInterval(4 * minute)), to: sam, at: earlier), to: alex, at: earlier)
    var samSettings = sam.state.settings
    samSettings.labels[Level.spicier.rawValue] = "Thinking of you, a lot"
    _ = sam.updateSettings(samSettings, at: now)
    let fresh = now.addingTimeInterval(-2 * minute)
    _ = deliver(try! sam.send(.spicier, at: fresh), to: alex, at: fresh)
}

func visitIn(days: Double, length: Double, setBy engine: Engine, telling other: Engine) {
    let calendar = Calendar.current
    let plan = VisitPlan(
        start: calendar.startOfDay(for: now.addingTimeInterval(days * day)),
        end: calendar.startOfDay(for: now.addingTimeInterval((days + length) * day))
    )
    let when = now.addingTimeInterval(-day)
    _ = deliver(engine.setVisit(plan, at: when), to: other, at: when)
}

struct Scene {
    var name: String
    var store: Store
    var page: MenuView.Page = .home
    var settingsScrollTo: String? = nil
    var connected = true
}

let scenes: [Scene] = [
    Scene(name: "1-pairing", store: Store(), connected: false),
    Scene(name: "2-waiting-for-them", store: {
        var store = Store()
        store.pair = PairSecret.generate()
        store.engine.settings.myName = "Alex"
        return store
    }()),
    Scene(name: "3-home", store: paired { alex, sam in
        visitIn(days: 12, length: 4, setBy: sam, telling: alex)
        evening(alex, sam)
    }),
    Scene(name: "4-they-are-away", store: paired { alex, sam in
        visitIn(days: 12, length: 4, setBy: sam, telling: alex)
        var settings = sam.state.settings
        settings.phoneAlertsOn = true
        settings.phoneTopic = PairSecret.newTopic(prefix: "ember-phone-")
        _ = deliver(sam.updateSettings(settings, at: now.addingTimeInterval(-day)), to: alex, at: now)
        let away = now.addingTimeInterval(-25 * minute)
        _ = deliver(sam.setAway(true, at: away), to: alex, at: away)
        alex.setWatchForReturn(true)
    }),
    Scene(name: "5-together", store: paired { alex, sam in
        visitIn(days: -1, length: 3, setBy: alex, telling: sam)
        let fresh = now.addingTimeInterval(-1 * minute)
        _ = deliver(try! sam.send(.fire, at: fresh), to: alex, at: fresh)
    }),
    Scene(name: "6-busy-and-comedown", store: paired { alex, sam in
        visitIn(days: -3, length: 2, setBy: alex, telling: sam)
        _ = alex.setBusy(until: now.addingTimeInterval(90 * minute), at: now)
        _ = deliver(sam.setBusy(until: now.addingTimeInterval(40 * minute), at: now), to: alex, at: now)
    }),
    Scene(name: "7-visit-editor", store: paired { alex, sam in
        visitIn(days: 12, length: 4, setBy: sam, telling: alex)
    }, page: .visit),
    Scene(name: "8-settings", store: paired { alex, _ in
        var settings = alex.state.settings
        settings.labels[Level.spicier.rawValue] = "Thinking of you, a lot"
        settings.phoneAlertsOn = true
        settings.phoneTopic = PairSecret.newTopic(prefix: "ember-phone-")
        _ = alex.updateSettings(settings, at: now)
    }, page: .settings),
    Scene(name: "8b-settings-iphone", store: paired { alex, _ in
        var settings = alex.state.settings
        settings.phoneAlertsOn = true
        settings.phoneTopic = PairSecret.newTopic(prefix: "ember-phone-")
        _ = alex.updateSettings(settings, at: now)
    }, page: .settings, settingsScrollTo: "bottom"),
    Scene(name: "9-version-warning", store: paired { alex, sam in
        var snapshot = sam.snapshot(at: now)
        snapshot.protocolVersion = Wire.protocolVersion + 1
        snapshot.appVersion = "0.3.0"
        _ = alex.receive(Envelope(id: UUID(), from: sam.deviceID, sentAt: now, payload: .snapshot(snapshot, wantsReply: false)), at: now)
    }),
]

/// Lets SwiftUI lay out, run onAppear, and draw.
func settle(_ seconds: TimeInterval = 0.6) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func png(_ rep: NSBitmapImageRep) -> Data? {
    rep.representation(using: .png, properties: [:])
}

/// True when the image is one flat colour: a capture that didn't work.
func isBlank(_ rep: NSBitmapImageRep) -> Bool {
    guard let first = rep.colorAt(x: 1, y: 1) else { return true }
    for y in stride(from: 0, to: rep.pixelsHigh, by: 7) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
            if let colour = rep.colorAt(x: x, y: y), colour != first { return false }
        }
    }
    return true
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.finishLaunching()

    var written = 0
    for scene in scenes {
        let file = scratch.appendingPathComponent(scene.name + ".json")
        scene.store.save(to: file)
        let model = AppModel(storeURL: file)
        if scene.connected { model.showAsConnected() }

        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let root = MenuView(model: model, page: scene.page, settingsScrollTo: scene.settingsScrollTo)
                .background(Color(nsColor: .windowBackgroundColor))
            let hosting = NSHostingView(rootView: root)
            hosting.appearance = appearance

            let window = NSWindow(
                contentRect: NSRect(x: 80, y: 80, width: 362, height: 700),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.appearance = appearance
            window.contentView = hosting
            window.orderFrontRegardless()
            settle()
            let size = hosting.fittingSize
            window.setContentSize(size)
            hosting.frame = NSRect(origin: .zero, size: size)
            settle()

            let base = "\(scene.name)-\(dark ? "dark" : "light")"
            var saved = false

            // 1. Ask the view to draw itself.
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                if !isBlank(rep), let data = png(rep) {
                    try? data.write(to: output.appendingPathComponent(base + ".png"))
                    saved = true
                } else {
                    print("  \(base): drawing the view came out blank, trying a window capture")
                }
            }

            // 2. Capture the window as the window server composited it.
            if !saved, let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
                let rep = NSBitmapImageRep(cgImage: image)
                if !isBlank(rep), let data = png(rep) {
                    try? data.write(to: output.appendingPathComponent(base + ".png"))
                    saved = true
                }
            }

            print(saved ? "  ok   \(base) \(Int(size.width))×\(Int(size.height))" : "  FAIL \(base): every capture was blank")
            if saved { written += 1 }
            window.orderOut(nil)
        }
    }
    try? FileManager.default.removeItem(at: scratch)
    print("\(written) screenshots in \(output.path)")
    exit(written == scenes.count * 2 ? 0 : 1)
}
