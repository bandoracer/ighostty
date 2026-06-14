import Foundation
import ServiceManagement

enum LoginItemService {
    static let plistName = "dev.ighostty.background.plist"
    private static let expectedLabel = "dev.ighostty.background"

    static var plistURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent(plistName)
    }

    static var availabilityIssue: String? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return "Start at login is only available from the packaged iGhostty.app build."
        }
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return "Start at login is unavailable because the login item plist is missing from this app bundle."
        }
        guard let plist = readBundledPlist() else {
            return "Start at login is unavailable because the bundled login item plist could not be read."
        }
        guard plist["Label"] as? String == expectedLabel else {
            return "Start at login is unavailable because the bundled login item plist has the wrong label."
        }
        guard let bundleProgram = plist["BundleProgram"] as? String, !bundleProgram.isEmpty else {
            return "This app bundle contains an outdated login item. Rebuild iGhostty.app before enabling start at login."
        }
        return nil
    }

    static var status: SMAppService.Status {
        guard availabilityIssue == nil else { return .notFound }
        return agent.status
    }

    static func setEnabled(_ enabled: Bool) throws {
        if let issue = availabilityIssue {
            throw LoginItemServiceError.unavailable(issue)
        }
        if enabled {
            try agent.register()
        } else {
            try agent.unregister()
        }
    }

    private static var agent: SMAppService {
        SMAppService.agent(plistName: plistName)
    }

    private static func readBundledPlist() -> [String: Any]? {
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
}

enum LoginItemServiceError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}
