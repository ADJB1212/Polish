//
//  Commands.swift
//  Polish
//
//  Created by Andrew Jaffe on 3/19/25.
//

import Darwin
import Foundation

class Commands {
    private static var recentCommands = [String: Date]()
    private static let commandCooldown: TimeInterval = 5.0
    private static let commandQueueKey = DispatchSpecificKey<Bool>()
    private static let commandQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.polish.commandQueue", attributes: [])
        queue.setSpecific(key: commandQueueKey, value: true)
        return queue
    }()

    static func runBrewCleanup(completion: @escaping (String) -> Void) {

        if !checkSystemResources() {
            completion("System resources are low. Please try again later.")
            return
        }

        var fullOutput = "Starting Homebrew Cleaning...\n"
        completion(fullOutput)

        let cmd1 = "PATH=$PATH:/usr/local/bin:/opt/homebrew/bin brew cleanup"
        let cmd2 = "PATH=$PATH:/usr/local/bin:/opt/homebrew/bin brew autoremove"

        let brewCheckCommand = "command -v brew"
        safeRunCommandSequential(brewCheckCommand, timeout: 10) { brewCheckOutput, brewCheckError in
            if let error = brewCheckError {
                fullOutput += "\nError: Homebrew is not installed or not in PATH."
                fullOutput += "Details: \(error.localizedDescription)\n"
                completion(fullOutput)
                return
            }

            fullOutput += "\nRunning: brew cleanup\n"
            completion(fullOutput)

            safeRunCommandSequential(cmd1, timeout: 180) { output1, error1 in
                if let error = error1 {
                    fullOutput += "Warning during brew cleanup: \(error.localizedDescription)\n"
                    fullOutput += "Output: \(output1)\n"
                    fullOutput += "(Continuing with next step anyway)\n"
                } else {
                    fullOutput += "\(output1)\n"
                }
                completion(fullOutput)

                fullOutput += "\nRunning: brew autoremove\n"
                completion(fullOutput)

                safeRunCommandSequential(cmd2, timeout: 30) { output2, error2 in
                    if let error = error2 {
                        fullOutput +=
                            "Warning during brew autoremove: \(error.localizedDescription)\n"
                        fullOutput += "Output: \(output2)\n"
                        fullOutput += "(Continuing with next step anyway)\n"
                    } else {
                        fullOutput += "\(output2)\n"
                    }
                    completion(fullOutput)

                }
            }
        }
    }

    static func runPipCommandForAllPythons(
        pipCommand: String, completion: @escaping (String) -> Void
    ) {

        if !checkSystemResources() {
            completion("System resources are low. Please try again later.")
            return
        }

        if pipCommand.contains("rm") || pipCommand.contains("sudo") || pipCommand.contains(";") {
            completion("Unsafe pip command detected. Operation aborted.")
            return
        }

        if isDuplicateCommand("pip_\(pipCommand)") {
            completion("This command was recently run. Please wait before trying again.")
            return
        }

        let command = """
            # Limit maximum subprocesses
            ulimit -u 50

            # Collect Python paths
            PYTHON_PATHS=$(
            {
                # Standard path executables
                which -a python python2 python3 python3.9 python3.10 python3.11 python3.12 2>/dev/null

                # Homebrew installations
                for brewpath in /usr/local/bin /opt/homebrew/bin; do
                    if [ -d "$brewpath" ]; then
                        ls -1 $brewpath/python* 2>/dev/null | grep -v config | head -n 5
                    fi
                done

                # Check pyenv if installed
                if command -v pyenv >/dev/null; then
                    pyenv which python 2>/dev/null
                    for ver in $(pyenv versions --bare 2>/dev/null | head -n 5); do
                        echo "$HOME/.pyenv/versions/$ver/bin/python"
                    done
                fi

                # Check conda environments if conda exists
                if command -v conda >/dev/null; then
                    conda info --envs 2>/dev/null | grep -v "#" | awk '{print $NF"/bin/python"}' | grep -v "^/" | head -n 5
                fi
            } | sort | uniq | head -n 10 | xargs -I{} sh -c 'if [ -x "{}" ] && [ -f "{}" ]; then echo "{}"; fi'
            )

            # If no Python installations found, try with default python3
            if [ -z "$PYTHON_PATHS" ]; then
                if command -v python3 >/dev/null; then
                    timeout 30 python3 -m pip \(pipCommand)
                fi
                exit 0
            fi

            # Process each Python installation with timeout
            echo "$PYTHON_PATHS" | while read python_exe; do
                # Skip empty lines
                [ -z "$python_exe" ] && continue

                echo "Running with $python_exe"
                $python_exe --version
                timeout 30 $python_exe -m pip \(pipCommand)
                echo "---------------------"
            done
            """

        safeRunCommand(command: command, timeout: 180, completion: completion)
    }

    static func removeFileOrDirectory(path: String, completion: @escaping (Any) -> Void) {

        if !checkSystemResources() {
            completion("System resources are low. Please try again later.")
            return
        }

        let pathForShell = Helper.escapePathForShell(path)

        if pathForShell.contains("..") || pathForShell.contains("*") || pathForShell == "/"
            || pathForShell.hasPrefix("/bin") || pathForShell.hasPrefix("/usr")
            || pathForShell.hasPrefix("/System") || pathForShell.hasPrefix("/Applications")
        {
            completion("Safety check failed: Cannot remove system directories")
            return
        }

        switch Helper.getPathType(path) {
        case .directory:
            safeRunCommand(command: "rm -rf \(pathForShell)", timeout: 30) { output, error in
                if let error = error {
                    completion("Error removing directory at \(pathForShell): \(error)")
                } else {
                    completion(output)
                }
            }
            break
        case .file:
            safeRunCommand(command: "rm -f \(pathForShell)", timeout: 10) { output, error in
                if let error = error {
                    completion("Error removing file at \(pathForShell): \(error)")
                } else {
                    completion(output)
                }
            }
            break
        case .notFound:
            completion("Error: Item not found at \(pathForShell)\n")
            break
        }
    }

    private static func safeRunCommand(
        command: String, timeout: TimeInterval, completion: @escaping (String, Error?) -> Void
    ) {
        commandQueue.async {

            if !checkSystemResources() {
                completion(
                    "",
                    NSError(
                        domain: "com.polish", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "System resources are low"]))
                return
            }

            if ProcessManager.shared.getActiveProcessCount() >= 5 {
                completion(
                    "",
                    NSError(
                        domain: "com.polish", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Too many active processes"]))
                return
            }

            ProcessManager.shared.waitForAvailableSlot()

            var outputText = ""
            let task = Process()
            let pipe = Pipe()

            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", "ulimit -u 50; " + command]
            task.standardOutput = pipe
            task.standardError = pipe

            let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timeoutTimer.setEventHandler {
                if task.isRunning {
                    task.terminate()
                    DispatchQueue.main.async {
                        completion(
                            outputText
                                + "\n\n*** Command timed out after \(Int(timeout)) seconds ***",
                            NSError(
                                domain: "com.polish", code: 3,
                                userInfo: [NSLocalizedDescriptionKey: "Command timed out"]))
                    }
                }
            }
            timeoutTimer.schedule(deadline: .now() + timeout)
            timeoutTimer.resume()

            let outHandle = pipe.fileHandleForReading

            ProcessManager.shared.addProcess(task)

            outHandle.readabilityHandler = { fileHandle in
                if let line = String(data: fileHandle.availableData, encoding: .utf8), !line.isEmpty
                {
                    DispatchQueue.main.async { outputText += line }
                }
            }

            do {
                try task.run()

                DispatchQueue.global(qos: .background).async {
                    task.waitUntilExit()

                    timeoutTimer.cancel()

                    ProcessManager.shared.removeProcess(task)

                    DispatchQueue.main.async {
                        outHandle.readabilityHandler = nil

                        try? pipe.fileHandleForReading.close()
                        try? pipe.fileHandleForWriting.close()

                        if task.terminationStatus == 0 {
                            completion(outputText, nil)
                        } else {
                            let error = NSError(
                                domain: "com.polish", code: Int(task.terminationStatus),
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "Command failed with status \(task.terminationStatus)"
                                ])
                            completion(outputText, error)
                        }
                    }
                }
            } catch {

                timeoutTimer.cancel()

                ProcessManager.shared.removeProcess(task)

                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()

                DispatchQueue.main.async {
                    outHandle.readabilityHandler = nil
                    completion("Error: \(error.localizedDescription)", error)
                }
            }
        }
    }

    private static func safeRunCommand(
        command: String, timeout: TimeInterval, completion: @escaping (String) -> Void
    ) {
        safeRunCommand(command: command, timeout: timeout) { output, error in
            if let error = error {
                completion("\(output)\nError: \(error.localizedDescription)")
            } else {
                completion(output)
            }
        }
    }

    static func safeRunCommandSequential(
        _ command: String, timeout: TimeInterval, completion: @escaping (String, Error?) -> Void
    ) {
        commandQueue.async {

            print("Executing command: \(command)")

            if !checkSystemResources() {
                completion(
                    "System resources are low. Command not executed: \(command)",
                    NSError(
                        domain: "com.polish", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "System resources are low"]))
                return
            }

            ProcessManager.shared.waitForAvailableSlot()

            var outputText = ""
            let task = Process()
            let pipe = Pipe()

            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", command]
            task.standardOutput = pipe
            task.standardError = pipe

            var env = ProcessInfo.processInfo.environment
            let pathExt = ":/usr/local/bin:/opt/homebrew/bin"
            env["PATH"] = (env["PATH"] ?? "") + pathExt
            task.environment = env

            let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timeoutTimer.setEventHandler {
                if task.isRunning {
                    print("Command timed out: \(command)")
                    task.terminate()
                    DispatchQueue.main.async {
                        completion(
                            outputText
                                + "\n\n*** Command timed out after \(Int(timeout)) seconds ***",
                            NSError(
                                domain: "com.polish", code: 3,
                                userInfo: [NSLocalizedDescriptionKey: "Command timed out"]))
                    }
                }
            }
            timeoutTimer.schedule(deadline: .now() + timeout)
            timeoutTimer.resume()

            let outHandle = pipe.fileHandleForReading

            ProcessManager.shared.addProcess(task)

            outHandle.readabilityHandler = { fileHandle in
                let availableData = fileHandle.availableData
                if availableData.isEmpty { return }

                if let line = String(data: availableData, encoding: .utf8) {

                    DispatchQueue.main.async {
                        outputText += line
                        print("Command output: \(line)")
                    }
                }
            }

            do {
                try task.run()

                DispatchQueue.global(qos: .background).async {
                    task.waitUntilExit()
                    let status = task.terminationStatus
                    print("Command completed with status: \(status)")

                    timeoutTimer.cancel()

                    ProcessManager.shared.removeProcess(task)

                    DispatchQueue.main.async {
                        outHandle.readabilityHandler = nil

                        try? pipe.fileHandleForReading.close()
                        try? pipe.fileHandleForWriting.close()

                        if status == 0 {
                            completion(outputText, nil)
                        } else {

                            let error = NSError(
                                domain: "com.polish", code: Int(status),
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "Command failed with status \(status)"
                                ])
                            completion(outputText, error)
                        }
                    }
                }
            } catch {
                print("Failed to run command: \(error.localizedDescription)")

                timeoutTimer.cancel()

                ProcessManager.shared.removeProcess(task)

                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()

                DispatchQueue.main.async {
                    outHandle.readabilityHandler = nil
                    completion("Failed to execute command: \(error.localizedDescription)", error)
                }
            }
        }
    }

    static func runCommandSequential(_ command: String, completion: @escaping (String) -> Void) {
        safeRunCommandSequential(command, timeout: 60) { output, error in
            if let error = error {
                completion("\(output)\nError: \(error.localizedDescription)")
            } else {
                completion(output)
            }
        }
    }

    private static func isDuplicateCommand(_ commandKey: String) -> Bool {
        let now = Date()
        var isDuplicate = false

        commandQueue.sync {

            recentCommands = recentCommands.filter {
                now.timeIntervalSince($0.value) < commandCooldown
            }

            if let lastRun = recentCommands[commandKey],
                now.timeIntervalSince(lastRun) < commandCooldown
            {
                isDuplicate = true
            } else {

                recentCommands[commandKey] = now
            }
        }

        return isDuplicate
    }

    static func checkSystemResources() -> Bool {

        var totalSize: Double = 0
        var stats1 = host_basic_info()
        var count1 = UInt32(
            MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats1) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count1)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count1)
            }
        }

        if kerr == KERN_SUCCESS { totalSize = Double(stats1.max_mem) }

        var count = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()

        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let active = Double(stats.active_count) * Double(vm_page_size)
            let speculative = Double(stats.speculative_count) * Double(vm_page_size)
            let inactive = Double(stats.inactive_count) * Double(vm_page_size)
            let wired = Double(stats.wire_count) * Double(vm_page_size)
            let compressed = Double(stats.compressor_page_count) * Double(vm_page_size)
            let purgeable = Double(stats.purgeable_count) * Double(vm_page_size)
            let external = Double(stats.external_page_count) * Double(vm_page_size)
            let swapins = Int64(stats.swapins)
            let swapouts = Int64(stats.swapouts)

            let used = active + inactive + speculative + wired + compressed - purgeable - external
            let free = totalSize - used

            var cpuUsage = CPU.systemUsage().user / 100

            let processCount = ProcessManager.shared.getActiveProcessCount()

            let memoryThreshold = 0.85
            let cpuThreshold = 0.80
            let processThreshold = 8

            print("Memory usage: \(used / totalSize)")
            print("CPU Usage: \(cpuUsage)")
            print("Processes: \(processCount)")

            let memoryOK = (used / totalSize) < memoryThreshold
            let cpuOK = cpuUsage < cpuThreshold
            let processCountOK = processCount < processThreshold

            return memoryOK && cpuOK && processCountOK
        }

        return true
    }
}

class ProcessManager {
    static let shared = ProcessManager()

    private let maxConcurrentProcesses = 5
    private let maxProcessTimeSeconds = 60
    private let processCheckInterval: TimeInterval = 1.0

    private var activeProcesses = [(process: Process, launchDate: Date)]()
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.polish.processManager", attributes: .concurrent)
    private let semaphore: DispatchSemaphore

    private init() {
        semaphore = DispatchSemaphore(value: maxConcurrentProcesses)
        startMonitoring()
    }

    deinit { stopMonitoring() }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: processCheckInterval, repeats: true) {
            [weak self] _ in self?.checkProcesses()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkProcesses() {
        queue.async { [weak self] in
            guard let self = self else { return }

            let processesCopy = self.queue.sync { return self.activeProcesses }

            for (process, launchDate) in processesCopy {

                if Date().timeIntervalSince(launchDate) > TimeInterval(self.maxProcessTimeSeconds) {

                    if process.isRunning {
                        process.terminate()
                        print(
                            "Terminated long-running process after \(Date().timeIntervalSince(launchDate)) seconds"
                        )
                    }

                    self.removeProcess(process)
                }
            }
        }
    }

    func addProcess(_ process: Process) {
        queue.async(flags: .barrier) { [weak self] in
            self?.activeProcesses.append((process: process, launchDate: Date()))
        }
    }

    func removeProcess(_ process: Process) {
        queue.async(flags: .barrier) { [weak self] in
            self?.activeProcesses.removeAll(where: { $0.process === process })
            self?.semaphore.signal()
        }
    }

    func waitForAvailableSlot() {

        semaphore.wait()
    }

    func getActiveProcessCount() -> Int {
        var count = 0
        queue.sync { count = activeProcesses.count }
        return count
    }

    func terminateAllProcesses() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            for (process, _) in self.activeProcesses {
                if process.isRunning { process.terminate() }
            }

            self.activeProcesses.removeAll()

            for _ in 0..<self.maxConcurrentProcesses { self.semaphore.signal() }
        }
    }
}
