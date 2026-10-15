import AppKit

@main
@MainActor enum VocumeApp {
    static func main() {
        signal(SIGPIPE, SIG_IGN)  // a CLI exiting mid-write should be an error, not a crash
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu-bar only, no Dock icon
        app.run()
    }
}
