import Foundation

@MainActor func run() {
let colors: [String: @MainActor () -> Bool] = [
    "system": SMCComm.MagSafe.setSystem,
    "off": SMCComm.MagSafe.setOff,
    "green": SMCComm.MagSafe.setGreen,
    "orange": SMCComm.MagSafe.setOrange,
    "orange-slow": SMCComm.MagSafe.setOrangeSlowBlink,
    "orange-fast": SMCComm.MagSafe.setOrangeFastBlink,
    "orange-blink-off": SMCComm.MagSafe.setOrangeBlinkOff,
]

let alternate = CommandLine.arguments.count >= 2 && CommandLine.arguments[1] == "orange-green"
guard CommandLine.arguments.count >= 2, alternate || colors[CommandLine.arguments[1]] != nil else {
    FileHandle.standardError.write(
        "usage: sudo magled {\((colors.keys.sorted() + ["orange-green [seconds]"]).joined(separator: "|"))}\n".data(using: .utf8)!
    )
    exit(2)
}
guard getuid() == 0 else { print("run as root"); exit(1) }
guard SMCComm.start() else { print("cannot open AppleSMC"); exit(1) }
SMCComm.MagSafe.prepare()
guard SMCComm.MagSafe.supported else { print("ACLC key not supported on this Mac"); exit(1) }
if alternate {
    // ACLC has no two-colour blink, so flip green/orange until Ctrl-C, then hand the LED back.
    let period = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 0.5 : 0.5
    signal(SIGINT, SIG_IGN)
    let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sig.setEventHandler { _ = SMCComm.MagSafe.setSystem(); exit(0) }
    sig.resume()
    var green = true
    Timer.scheduledTimer(withTimeInterval: period, repeats: true) { _ in
        _ = green ? SMCComm.MagSafe.setGreen() : SMCComm.MagSafe.setOrange()
        green.toggle()
    }
    RunLoop.main.run()
}
exit(colors[CommandLine.arguments[1]]!() ? 0 : 1)
}
MainActor.assumeIsolated { run() }
