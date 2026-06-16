import Foundation

enum GhosttySSHCLI {
    static func runIfNeeded(arguments: [String]) -> Int32? {
        guard arguments.count >= 2 else { return nil }
        switch arguments[1] {
        case "+ssh":
            return runSSH(Array(arguments.dropFirst(2)))
        case "+ssh-cache":
            return runCache(Array(arguments.dropFirst(2)))
        default:
            return nil
        }
    }

    private struct SSHOptions {
        var forwardEnv = true
        var terminfo = true
        var cache = true
        var sshPath = "/usr/bin/ssh"
        var sshArgs: [String] = []
    }

    private static func runSSH(_ rawArgs: [String]) -> Int32 {
        var opts = SSHOptions()
        var args = rawArgs
        if args.first == "--" { args.removeFirst() }

        while let first = args.first {
            if first == "--" {
                args.removeFirst()
                break
            }
            if first == "--help" || first == "-h" {
                printSSHHelp()
                return 0
            }
            if first.hasPrefix("--forward-env=") {
                opts.forwardEnv = boolValue(String(first.dropFirst("--forward-env=".count)), default: true)
                args.removeFirst()
                continue
            }
            if first.hasPrefix("--terminfo=") {
                opts.terminfo = boolValue(String(first.dropFirst("--terminfo=".count)), default: true)
                args.removeFirst()
                continue
            }
            if first.hasPrefix("--cache=") {
                opts.cache = boolValue(String(first.dropFirst("--cache=".count)), default: true)
                args.removeFirst()
                continue
            }
            if first.hasPrefix("--ssh=") {
                opts.sshPath = String(first.dropFirst("--ssh=".count))
                args.removeFirst()
                continue
            }
            break
        }
        opts.sshArgs = args

        guard FileManager.default.isExecutableFile(atPath: opts.sshPath) else {
            FileHandle.standardError.writeLine("iGhostty +ssh: ssh executable is not executable: \(opts.sshPath)")
            return 2
        }
        guard !opts.sshArgs.isEmpty else {
            FileHandle.standardError.writeLine("iGhostty +ssh: missing ssh destination")
            return 2
        }

        var term = TerminalTerm.legacyDefault
        if opts.terminfo, let destination = resolveDestination(sshPath: opts.sshPath, args: opts.sshArgs) {
            let cache = SSHCache.load()
            let cached = opts.cache && cache.contains(destination)
            if cached || installTerminfo(sshPath: opts.sshPath, args: opts.sshArgs) {
                term = TerminalTerm.ghostty
                if opts.cache, !cached {
                    var updated = cache
                    updated.add(destination)
                    updated.save()
                }
            } else {
                FileHandle.standardError.writeLine("iGhostty +ssh: warning: failed to install xterm-ghostty terminfo; falling back to xterm-256color")
            }
        }

        return runProcess(opts.sshPath, args: finalSSHArgs(opts: opts), environmentOverrides: sshEnvironment(term: term))
    }

    private static func finalSSHArgs(opts: SSHOptions) -> [String] {
        var args: [String] = []
        if opts.forwardEnv {
            args += ["-o", "SendEnv=COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION"]
        }
        args += opts.sshArgs
        return args
    }

    private static func sshEnvironment(term: String) -> [String: String] {
        var env: [String: String] = [
            "TERM": term,
            "COLORTERM": "truecolor",
            "TERM_PROGRAM": "iGhostty",
            "TERM_PROGRAM_VERSION": appVersion,
        ]
        if let resourcesDir = GhosttyResources.resourcesDir {
            env["GHOSTTY_RESOURCES_DIR"] = resourcesDir.path
        }
        if let binDir = GhosttyResources.binDir {
            env["GHOSTTY_BIN_DIR"] = binDir.path
        }
        return env
    }

    private static func installTerminfo(sshPath: String, args: [String]) -> Bool {
        guard let sourceURL = GhosttyResources.terminfoSourceURL,
              let terminfo = try? Data(contentsOf: sourceURL) else { return false }
        let remote = "mkdir -p ~/.terminfo 2>/dev/null && tic -x - >/dev/null 2>&1"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: sshPath)
        proc.arguments = args + [remote]
        proc.standardInput = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            if let input = proc.standardInput as? Pipe {
                input.fileHandleForWriting.write(terminfo)
                try? input.fileHandleForWriting.close()
            }
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func resolveDestination(sshPath: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: sshPath)
        proc.arguments = ["-G"] + args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return fallbackDestination(args) }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            var user = NSUserName()
            var host: String?
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                if parts[0] == "user" { user = parts[1] }
                if parts[0] == "hostname" { host = parts[1] }
            }
            if let host, !host.isEmpty { return "\(user)@\(host)" }
        } catch {}
        return fallbackDestination(args)
    }

    private static func fallbackDestination(_ args: [String]) -> String? {
        var skipNext = false
        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if ["-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l", "-m", "-O", "-o", "-p", "-Q", "-R", "-S", "-W", "-w"].contains(arg) {
                skipNext = true
                continue
            }
            if arg.hasPrefix("-") { continue }
            return arg.contains("@") ? arg : "\(NSUserName())@\(arg)"
        }
        return nil
    }

    private static func runProcess(_ path: String, args: [String], environmentOverrides: [String: String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environmentOverrides { env[key] = value }
        proc.environment = env
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus
        } catch {
            FileHandle.standardError.writeLine("iGhostty +ssh: \(error.localizedDescription)")
            return 1
        }
    }

    private static func runCache(_ args: [String]) -> Int32 {
        if args.contains("--help") || args.contains("-h") {
            printCacheHelp()
            return 0
        }
        var cache = SSHCache.load()
        var handled = false
        for arg in args {
            if arg.hasPrefix("--host=") {
                let host = String(arg.dropFirst("--host=".count))
                print(cache.contains(host) ? "\(host): cached" : "\(host): not cached")
                handled = true
            } else if arg.hasPrefix("--add=") {
                cache.add(String(arg.dropFirst("--add=".count)))
                handled = true
            } else if arg.hasPrefix("--remove=") {
                cache.remove(String(arg.dropFirst("--remove=".count)))
                handled = true
            } else if arg == "--clear" {
                cache.removeAll()
                handled = true
            } else if arg.hasPrefix("--expire-days=") {
                let days = Int(arg.dropFirst("--expire-days=".count)) ?? 0
                cache.expireDays = max(0, days)
                handled = true
            }
        }
        if handled {
            cache.save()
        } else {
            for entry in cache.entries.sorted() {
                print(entry)
            }
        }
        return 0
    }

    private static func boolValue(_ raw: String, default fallback: Bool) -> Bool {
        switch raw.lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return fallback
        }
    }

    private static func printSSHHelp() {
        print("""
        Usage: iGhostty +ssh [--forward-env=false] [--terminfo=false] [--cache=false] [--ssh=PATH] -- HOST [SSH_ARGS...]
        """)
    }

    private static func printCacheHelp() {
        print("""
        Usage: iGhostty +ssh-cache [--host=USER@HOST] [--add=USER@HOST] [--remove=USER@HOST] [--clear] [--expire-days=N]
        """)
    }
}

private struct SSHCache {
    var entries: Set<String> = []
    var expireDays = 0

    static var url: URL {
        let dir = SettingsStore.shared.directoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ssh-terminfo-cache.txt")
    }

    static func load() -> SSHCache {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return SSHCache() }
        var cache = SSHCache()
        for line in text.split(separator: "\n") {
            if line.hasPrefix("expire-days=") {
                cache.expireDays = Int(line.dropFirst("expire-days=".count)) ?? 0
            } else if !line.isEmpty {
                cache.entries.insert(String(line))
            }
        }
        return cache
    }

    func contains(_ host: String) -> Bool {
        entries.contains(host)
    }

    mutating func add(_ host: String) {
        entries.insert(host)
    }

    mutating func remove(_ host: String) {
        entries.remove(host)
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    func save() {
        let lines = ["expire-days=\(expireDays)"] + entries.sorted()
        try? lines.joined(separator: "\n").write(to: Self.url, atomically: true, encoding: .utf8)
    }
}

private extension FileHandle {
    func writeLine(_ line: String) {
        if let data = (line + "\n").data(using: .utf8) {
            write(data)
        }
    }
}
