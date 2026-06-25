import Foundation
import ServiceManagement
import Security
import Darwin

enum LoginItemService {
    static let plistName = "dev.ighostty.background.plist"
    private static let expectedLabel = "dev.ighostty.background"
    private static let registrationFingerprintKey = "iGhostty.loginItem.registrationFingerprint"

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
            removeLaunchdJobIfPresent()
            try agent.register()
            saveCurrentRegistrationFingerprint()
        } else {
            try agent.unregister()
            removeLaunchdJobIfPresent()
            UserDefaults.standard.removeObject(forKey: registrationFingerprintKey)
        }
    }

    static func refreshRegistrationIfNeeded() {
        guard availabilityIssue == nil, agent.status == .enabled else { return }
        guard let currentFingerprint = currentSigningFingerprint else {
            NSLog("iGhostty login item refresh skipped because the current code signature could not be inspected")
            return
        }

        let registeredFingerprint = UserDefaults.standard.string(forKey: registrationFingerprintKey)
        guard registeredFingerprint != currentFingerprint else { return }

        do {
            try agent.unregister()
            removeLaunchdJobIfPresent()
            try agent.register()
            UserDefaults.standard.set(currentFingerprint, forKey: registrationFingerprintKey)
            NSLog("iGhostty login item registration refreshed for current code signature")
        } catch {
            NSLog("iGhostty login item registration refresh failed: %@", error.localizedDescription)
        }
    }

    private static var agent: SMAppService {
        SMAppService.agent(plistName: plistName)
    }

    private static func saveCurrentRegistrationFingerprint() {
        guard let currentSigningFingerprint else { return }
        UserDefaults.standard.set(currentSigningFingerprint, forKey: registrationFingerprintKey)
    }

    private static func removeLaunchdJobIfPresent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(expectedLabel)"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("iGhostty launchd login item cleanup failed to start: %@", error.localizedDescription)
            return
        }

        guard process.terminationStatus != 0, process.terminationStatus != 113 else { return }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        NSLog(
            "iGhostty launchd login item cleanup exited with status %d %@",
            process.terminationStatus,
            message
        )
    }

    private static var currentSigningFingerprint: String? {
        var staticCode: SecStaticCode?
        let executableURL = Bundle.main.bundleURL as CFURL
        guard SecStaticCodeCreateWithPath(executableURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        ) == errSecSuccess,
              let info = signingInfo as? [String: Any] else {
            return nil
        }

        let identifier = info[kSecCodeInfoIdentifier as String] as? String
            ?? Bundle.main.bundleIdentifier
            ?? "unknown"
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String ?? "adhoc"
        let cdhash = (info[kSecCodeInfoUnique as String] as? Data)?.map { String(format: "%02x", $0) }.joined()
            ?? "unknown"
        return "\(identifier):\(team):\(cdhash)"
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
