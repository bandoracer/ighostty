import AppKit

if let status = GhosttySSHCLI.runIfNeeded(arguments: CommandLine.arguments) {
    exit(status)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
