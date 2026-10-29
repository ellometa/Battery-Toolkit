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
let isDaemon = args.count == 3 && args[1] == "daemon" && UInt32(args[2]) != nil
let isScan = args.count >= 2 && args[1] == "scan"
guard args.count >= 2, alternate || isRaw || isScan || isDaemon || colors[CommandLine.arguments[1]] != nil else {
    FileHandle.standardError.write(
        "usage: sudo magled {\((colors.keys.sorted() + ["orange-green [seconds]", "raw <byte>", "scan [seconds]", "daemon <uid>"]).joined(separator: "|"))}\n".data(using: .utf8)!
    )
    exit(2)
}
guard getuid() == 0 else { print("run as root"); exit(1) }
guard SMCComm.start() else { print("cannot open AppleSMC"); exit(1) }
SMCComm.MagSafe.prepare()
guard SMCComm.MagSafe.supported else { print("ACLC key not supported on this Mac"); exit(1) }
let key = SMCComm.Key("A", "C", "L", "C")
if isDaemon {
    // Root helper for the GUI: a 0600 unix socket owned by <uid>. One connection = one line holding 0-7, written to ACLC.
    // Only 0-7 are accepted (scan showed the SMC ignores everything above), so the socket can't write anything else.
    let path = "/var/run/magled.sock"
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        _ = path.withCString { strlcpy(buf.baseAddress!.assumingMemoryBound(to: CChar.self), $0, buf.count) }
    }
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0, chown(path, uid_t(args[2])!, 0) == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
        print("cannot create \(path)"); exit(1)
    }
    let srv = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
    srv.setEventHandler {
        let c = accept(fd, nil, nil)
        guard c >= 0 else { return }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 16)
        let n = read(c, &buf, 15)
        var reply = "err\n"
        if n > 0, let s = String(bytes: buf[0..<n], encoding: .utf8),
           let v = UInt8(s.trimmingCharacters(in: .whitespacesAndNewlines)), v <= 7 {
            // The SMC applies writes asynchronously, so writeKey's immediate read-back is not a reliable result.
            _ = SMCComm.writeKey(key: key, bytes: [v])
            reply = "ok\n"
        }
        _ = write(c, reply, reply.utf8.count)
        close(c)
    }
    srv.resume()
    signal(SIGTERM, SIG_IGN)
    let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    term.setEventHandler { _ = SMCComm.MagSafe.setSystem(); unlink(path); exit(0) }
    term.resume()
    dispatchMain()
}
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
        // The SMC applies a write asynchronously: reading straight back returns the previous state, so read after the hold.
        _ = SMCComm.writeKey(key: key, bytes: [v])
        Thread.sleep(forTimeInterval: hold)
        let rb = SMCComm.readKey(key: key, dataSize: 1)?.first
        let ok = rb == v
        if ok { accepted.append(v) }
        print(String(format: "0x%02X  %@  readback=%@", v, ok ? "accepted" : "rejected", rb.map { String(format: "0x%02X", $0) } ?? "?"))
        fflush(stdout)
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
