import Foundation

// Client for the root helper (`magled daemon <uid>`), which owns the SMC write.
enum LED {
    static let socketPath = "/var/run/magled.sock"
    static let label = "io.github.ellometa.magled"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let binPath = "/usr/local/libexec/magled"

    static var available: Bool { FileManager.default.fileExists(atPath: socketPath) }

    static func set(_ value: UInt8) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            _ = socketPath.withCString { strlcpy(buf.baseAddress!.assumingMemoryBound(to: CChar.self), $0, buf.count) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else { return false }
        let line = "\(value)\n"
        _ = write(fd, line, line.utf8.count)
        var buf = [UInt8](repeating: 0, count: 8)
        return read(fd, &buf, 7) > 0 && buf[0] == UInt8(ascii: "o")
    }

    // Both return an error message, or nil on success. The only privileged step is one admin prompt.
    static func install() -> String? {
        guard let bin = Bundle.main.url(forResource: "magled", withExtension: nil) else { return "magled binary missing from app" }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(label)</string>
        <key>ProgramArguments</key><array><string>\(binPath)</string><string>daemon</string><string>\(getuid())</string></array>
        <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
        </dict></plist>
        """
        let tmp = NSTemporaryDirectory() + "magled.plist"
        guard (try? plist.write(toFile: tmp, atomically: true, encoding: .utf8)) != nil else { return "cannot write plist" }
        let cmd = [
            "mkdir -p /usr/local/libexec",
            "cp \(q(bin.path)) \(binPath)", "chmod 755 \(binPath)",
            "cp \(q(tmp)) \(plistPath)", "chown root:wheel \(plistPath)", "chmod 644 \(plistPath)",
            "(launchctl bootout system \(plistPath) 2>/dev/null || true)",
            "launchctl bootstrap system \(plistPath)",
        ].joined(separator: " && ")
        return admin(cmd)
    }

    static func uninstall() -> String? {
        admin("(launchctl bootout system \(plistPath) 2>/dev/null || true); rm -f \(plistPath) \(binPath) \(socketPath)")
    }

    private static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func admin(_ shell: String) -> String? {
        let esc = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(esc)\" with administrator privileges")?.executeAndReturnError(&err)
        return err?[NSAppleScript.errorMessage] as? String
    }
}
