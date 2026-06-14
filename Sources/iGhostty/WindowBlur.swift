import AppKit
import Darwin

/// iTerm2-style background blur: blurs whatever is behind a transparent window,
/// with an adjustable radius. macOS exposes this only through a private
/// CoreGraphics SkyLight call (`CGSSetWindowBackgroundBlurRadius`), the same one
/// iTerm2 and Terminal use. We resolve it at runtime via `dlsym` so there is no
/// link-time dependency on a private symbol.
enum WindowBlur {
    private typealias DefaultConnFn = @convention(c) () -> UInt32
    private typealias SetBlurFn = @convention(c) (UInt32, UInt32, UInt) -> Int32

    private static let defaultConnection: DefaultConnFn? = symbol("CGSDefaultConnectionForThread")
    private static let setBlurRadius: SetBlurFn? = symbol("CGSSetWindowBackgroundBlurRadius")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle = dlopen(nil, RTLD_NOW), let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }

    /// Sets (or clears, with radius 0) the background blur for a window.
    static func apply(to window: NSWindow, radius: Int) {
        guard window.windowNumber > 0,
              let connection = defaultConnection?(),
              let setBlurRadius else { return }
        _ = setBlurRadius(connection, UInt32(window.windowNumber), UInt(max(0, radius)))
    }
}
