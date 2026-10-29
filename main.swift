import Foundation

var stopScan = false

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
let args = CommandLine.arguments
let isRaw = args.count == 3 && args[1] == "raw"
let isScan = args.count >= 2 && args[1] == "scan"
guard args.count >= 2, alternate || isRaw || isScan || colors[CommandLine.arguments[1]] != nil else {
    FileHandle.standardError.write(
        "usage: sudo magled {\((colors.keys.sorted() + ["orange-green [seconds]", "raw <byte>", "scan [seconds]"]).joined(separator: "|"))}\n".data(using: .utf8)!
    )
    exit(2)
}
guard getuid() == 0 else { print("run as root"); exit(1) }
guard SMCComm.start() else { print("cannot open AppleSMC"); exit(1) }
SMCComm.MagSafe.prepare()
guard SMCComm.MagSafe.supported else { print("ACLC key not supported on this Mac"); exit(1) }
let key = SMCComm.Key("A", "C", "L", "C")
if isRaw {
    let t = args[2]
    guard let v = t.hasPrefix("0x") ? UInt8(t.dropFirst(2), radix: 16) : UInt8(t) else { print("byte 0-255 or 0xNN"); exit(2) }
    exit(SMCComm.writeKey(key: key, bytes: [v]) ? 0 : 1)
}
if isScan {
    // Write every byte 0x00-0xFF to ACLC, hold it so you can watch the LED, record which values the SMC keeps.
    let hold = args.count > 2 ? Double(args[2]) ?? 2.0 : 2.0
    signal(SIGINT) { _ in stopScan = true }
    var accepted: [UInt8] = []
    for v in UInt8.min...UInt8.max {
        if stopScan { break }
        let ok = SMCComm.writeKey(key: key, bytes: [v])
        let rb = SMCComm.readKey(key: key, dataSize: 1)?.first
        if ok { accepted.append(v) }
        print(String(format: "0x%02X  %@  readback=%@", v, ok ? "accepted" : "rejected", rb.map { String(format: "0x%02X", $0) } ?? "?"))
        fflush(stdout)
        Thread.sleep(forTimeInterval: hold)
    }
    _ = SMCComm.MagSafe.setSystem()
    print("accepted: " + accepted.map { String(format: "0x%02X", $0) }.joined(separator: " "))
    exit(0)
}
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
