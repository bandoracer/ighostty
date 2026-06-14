import Foundation
import Darwin

final class LocalPTYSession {
    private struct CStringArray {
        let base: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        let count: Int
    }

    private let queue = DispatchQueue(label: "dev.ighostty.pty", qos: .userInitiated)
    private let readQueue = DispatchQueue(label: "dev.ighostty.pty.read", qos: .userInitiated)
    private var io: DispatchIO?
    private var processMonitor: DispatchSourceProcess?
    private var childfd: Int32 = -1
    private(set) var shellPid: pid_t = 0
    private var startTime = Date()

    private let onOutput: (Data) -> Void
    private let onExit: (Int32?, UInt64) -> Void

    var isRunning: Bool {
        shellPid > 0 && childfd >= 0
    }

    init(onOutput: @escaping (Data) -> Void, onExit: @escaping (Int32?, UInt64) -> Void) {
        self.onOutput = onOutput
        self.onExit = onExit
    }

    func start(
        executable: String,
        args: [String],
        environment: [String],
        execName: String?,
        currentDirectory: String?,
        columns: Int,
        rows: Int
    ) {
        guard !isRunning else { return }

        var windowSize = winsize(
            ws_row: UInt16(max(rows, 1)),
            ws_col: UInt16(max(columns, 1)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        var argv = args
        argv.insert(execName ?? executable, at: 0)

        guard let launched = Self.fork(
            andExec: executable,
            args: argv,
            env: environment,
            currentDirectory: currentDirectory,
            desiredWindowSize: &windowSize
        ) else {
            DispatchQueue.main.async { [onExit] in onExit(nil, 0) }
            return
        }

        shellPid = launched.pid
        childfd = launched.masterFd
        startTime = Date()
        installProcessMonitor(pid: launched.pid)
        installReader(fd: launched.masterFd)
    }

    func send(_ data: Data) {
        guard childfd >= 0, !data.isEmpty else { return }
        let fd = childfd
        queue.async {
            data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var pointer = base.assumingMemoryBound(to: UInt8.self)
                var remaining = rawBuffer.count
                while remaining > 0 {
                    let written = Darwin.write(fd, pointer, remaining)
                    if written > 0 {
                        pointer = pointer.advanced(by: written)
                        remaining -= written
                    } else if errno == EINTR {
                        continue
                    } else {
                        break
                    }
                }
            }
        }
    }

    func send(_ bytes: ArraySlice<UInt8>) {
        send(Data(bytes))
    }

    func resize(columns: Int, rows: Int) {
        guard childfd >= 0 else { return }
        var windowSize = winsize(
            ws_row: UInt16(max(rows, 1)),
            ws_col: UInt16(max(columns, 1)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(childfd, TIOCSWINSZ, &windowSize)
    }

    func terminate() {
        let pid = shellPid
        tearDownIO()
        if pid > 0 {
            kill(pid, SIGTERM)
        }
    }

    private func installReader(fd: Int32) {
        let fdToClose = fd
        io = DispatchIO(type: .stream, fileDescriptor: fd, queue: queue) { _ in
            close(fdToClose)
        }
        io?.setLimit(lowWater: 1)
        io?.setLimit(highWater: 16 * 1024)
        readNext()
    }

    private func readNext() {
        io?.read(offset: 0, length: 16 * 1024, queue: readQueue) { [weak self] done, dispatchData, readErrno in
            guard let self else { return }
            if let dispatchData, dispatchData.count > 0 {
                let data = Self.data(from: dispatchData)
                DispatchQueue.main.async { [weak self] in
                    self?.onOutput(data)
                }
            }
            if done || readErrno != 0 {
                return
            }
            self.readNext()
        }
    }

    private func installProcessMonitor(pid: pid_t) {
        processMonitor = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        processMonitor?.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            _ = waitpid(pid, &status, WNOHANG)
            let runtime = UInt64(max(0, Date().timeIntervalSince(self.startTime) * 1000))
            let exitCode = Self.exitCode(fromWaitStatus: status)
            self.tearDownIO()
            DispatchQueue.main.async { [onExit] in
                onExit(exitCode, runtime)
            }
        }
        processMonitor?.resume()
    }

    private func tearDownIO() {
        processMonitor?.cancel()
        processMonitor = nil
        io?.close()
        io = nil
        childfd = -1
        shellPid = 0
    }

    private static func exitCode(fromWaitStatus status: Int32) -> Int32? {
        if status == 0 { return 0 }
        if (status & 0x7f) == 0 {
            return (status >> 8) & 0xff
        }
        let signal = status & 0x7f
        return signal == 0 ? nil : 128 + signal
    }

    private static func data(from dispatchData: DispatchData) -> Data {
        var data = Data()
        dispatchData.enumerateBytes { buffer, _, _ in
            data.append(contentsOf: buffer)
        }
        return data
    }

    private static func fork(
        andExec executable: String,
        args: [String],
        env: [String],
        currentDirectory: String?,
        desiredWindowSize: inout winsize
    ) -> (pid: pid_t, masterFd: Int32)? {
        guard let cArgs = allocateCStringArray(args),
              let cEnv = allocateCStringArray(env),
              let cExecutable = strdup(executable)
        else { return nil }

        var cCurrentDirectory: UnsafeMutablePointer<CChar>?
        if let currentDirectory {
            cCurrentDirectory = strdup(currentDirectory)
        }

        defer {
            freeCStringArray(cArgs)
            freeCStringArray(cEnv)
            free(cExecutable)
            if let cCurrentDirectory {
                free(cCurrentDirectory)
            }
        }

        var master: Int32 = 0
        let pid = forkpty(&master, nil, nil, &desiredWindowSize)
        if pid < 0 {
            return nil
        }
        if pid == 0 {
            if let cCurrentDirectory {
                _ = chdir(cCurrentDirectory)
            }
            _ = execve(cExecutable, cArgs.base, cEnv.base)
            _exit(127)
        }
        return (pid, master)
    }

    private static func allocateCStringArray(_ strings: [String]) -> CStringArray? {
        let base = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count + 1)
        var initialized = 0
        for (index, string) in strings.enumerated() {
            guard let duplicated = strdup(string) else {
                for cleanupIndex in 0 ..< initialized {
                    free(base[cleanupIndex])
                }
                base.deallocate()
                return nil
            }
            base[index] = duplicated
            initialized += 1
        }
        base[strings.count] = nil
        return CStringArray(base: base, count: strings.count)
    }

    private static func freeCStringArray(_ array: CStringArray) {
        for index in 0 ..< array.count {
            free(array.base[index])
        }
        array.base.deallocate()
    }
}
