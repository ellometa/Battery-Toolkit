import AppKit
import Foundation

struct LEDState {
    let value: UInt8
    let name: String
}

// Values 0-7 are the only ones the SMC keeps (measured with `magled scan`). 2 and 5 are not used by Battery Toolkit.
let ledStates: [LEDState] = [
    LEDState(value: 0, name: "System default"),
    LEDState(value: 1, name: "Off"),
    LEDState(value: 2, name: "Experimental 2"),
    LEDState(value: 3, name: "Green"),
    LEDState(value: 4, name: "Orange"),
    LEDState(value: 5, name: "Experimental 5"),
    LEDState(value: 6, name: "Orange, slow blink"),
    LEDState(value: 7, name: "Orange, fast blink"),
]

struct Step: Codable, Identifiable, Hashable {
    var id = UUID()
    var value: UInt8 = 3
    var ms = 400
}

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var steps: [Step]
    var loops = 5
}

struct EventConfig: Codable {
    var soundOn = true
    var soundPath: String? = nil // nil = bundled default
    var volume = 1.0
    var profileID: UUID? = nil
}

struct Settings: Codable {
    var profiles: [Profile]
    var onPlug = EventConfig()
    var onUnplug = EventConfig(soundOn: false)
    var muteSystemChime = true
    var builtInSpeakers: Bool? = true // nil/true = play on the built-in speakers even if headphones are the default output

    static func initial() -> Settings {
        let alt = Profile(name: "Orange / green", steps: [Step(value: 3, ms: 400), Step(value: 4, ms: 400)], loops: 5)
        let pulse = Profile(name: "Green pulse", steps: [Step(value: 3, ms: 300), Step(value: 1, ms: 300)], loops: 4)
        let warn = Profile(name: "Orange fast", steps: [Step(value: 7, ms: 2000)], loops: 1)
        var s = Settings(profiles: [alt, pulse, warn])
        s.onPlug.profileID = alt.id
        return s
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var settings: Settings { didSet { save() } }
    @Published var helperInstalled = LED.available
    @Published var plugged = Power.isAC()
    @Published var message = ""
    @Published var selection: UUID?

    private var generation = 0
    private var sound: NSSound?
    private var watcher: PowerWatcher?

    private static let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("magled")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.file), let s = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = s
        } else {
            settings = Settings.initial()
        }
        watcher = PowerWatcher { [weak self] in
            Task { @MainActor in self?.powerChanged() }
        }
        applyChimeMute()
    }

    // launchd starts PowerChime on demand when power is attached (and `disable` doesn't stop that), so it has to be
    // killed as it appears. Racy by nature: it plays only after it has checked the display is awake, which gives a window.
    nonisolated func killChime(for seconds: Double) {
        Task.detached {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                for a in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.PowerChime") { a.forceTerminate() }
                try? await Task.sleep(nanoseconds: 15_000_000)
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) { try? data.write(to: Self.file) }
    }

    func profile(_ id: UUID?) -> Profile? { settings.profiles.first { $0.id == id } }

    private func powerChanged() {
        let now = Power.isAC()
        guard now != plugged else { return }
        plugged = now
        if settings.muteSystemChime { killChime(for: 5) }
        fire(now ? settings.onPlug : settings.onUnplug)
    }

    func fire(_ c: EventConfig) {
        play(c)
        if let p = profile(c.profileID) { run(p) }
    }

    func play(_ c: EventConfig) {
        guard c.soundOn else { return }
        let url = c.soundPath.map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.url(forResource: "default-chime", withExtension: "m4a")
        guard let url, let s = NSSound(contentsOf: url, byReference: true) else {
            message = "Cannot load sound"
            return
        }
        s.volume = Float(c.volume)
        if settings.builtInSpeakers ?? true, let uid = Speakers.builtInUID() { s.playbackDeviceIdentifier = uid }
        sound?.stop()
        sound = s
        s.play()
    }

    // A newer run (or stop) bumps `generation`, which makes older loops quit without touching the LED again.
    func run(_ p: Profile) {
        generation += 1
        let mine = generation
        let steps = p.steps
        let loops = max(1, p.loops)
        Task.detached {
            func current() async -> Bool { await MainActor.run { self.generation == mine } }
            outer: for _ in 0..<loops {
                for s in steps {
                    if !(await current()) { return }
                    _ = LED.set(s.value)
                    try? await Task.sleep(nanoseconds: UInt64(max(20, s.ms)) * 1_000_000)
                }
            }
            if await current() { _ = LED.set(0) }
        }
    }

    func restoreLED() {
        generation += 1
        _ = LED.set(0)
    }

    // PowerChime is a per-user launch agent that SIP won't let us boot out. `disable` keeps it from loading at login;
    // `killChime` handles the on-demand launches. Re-enabling undoes it.
    func applyChimeMute() {
        let target = "gui/\(getuid())/com.apple.powerchime"
        let steps: [[String]] = settings.muteSystemChime
            ? [["/bin/launchctl", "disable", target], ["/usr/bin/killall", "-9", "PowerChime"]]
            : [["/bin/launchctl", "enable", target], ["/bin/launchctl", "kickstart", target]]
        for s in steps {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: s[0])
            p.arguments = Array(s.dropFirst())
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    func installHelper() {
        message = LED.install() ?? ""
        helperInstalled = LED.available
    }

    func removeHelper() {
        message = LED.uninstall() ?? ""
        helperInstalled = LED.available
    }
}
