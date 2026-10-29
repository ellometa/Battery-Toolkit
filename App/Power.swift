import Foundation
import IOKit.ps

enum Power {
    static func isAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        return IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? == kIOPSACPowerValue
    }
}

final class PowerWatcher {
    private let callback: () -> Void
    private var source: CFRunLoopSource?

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ ctx in
            Unmanaged<PowerWatcher>.fromOpaque(ctx!).takeUnretainedValue().callback()
        }, ctx)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    deinit { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) } }
}
