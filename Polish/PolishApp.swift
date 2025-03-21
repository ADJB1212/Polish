//
//  PolishApp.swift
//  Polish
//
//  Created by Andrew Jaffe on 3/19/25.
//

import Darwin
import SwiftUI

@main
struct PolishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene { WindowGroup { ContentView() } }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var memoryWarningObserver: NSObjectProtocol?
    private var memoryMonitorTimer: Timer?
    private let memoryThreshold: Double = 0.85

    func applicationDidFinishLaunching(_ notification: Notification) {
            // Set system resource limits
            raiseSystemLimits()
            
            // Print system diagnostics on startup
            let diagnostics = ProcessManager.shared.getSystemDiagnostics()
            print("STARTUP DIAGNOSTICS:\n\(diagnostics)")
            
            startMemoryMonitoring()
            
            memoryWarningObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("MemoryWarning"), object: nil, queue: .main
            ) { [weak self] _ in self?.handleResourceWarning() }
        }
        
        func applicationWillTerminate(_ notification: Notification) {
            // Clean up processes on app termination
            ProcessManager.shared.cleanupZombieProcesses()
            
            stopMemoryMonitoring()
            
            if let observer = memoryWarningObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        // Add this new method to increase system limits
        private func raiseSystemLimits() {
            // Attempt to raise the soft limit for open files and processes
            // This is safer than using ulimit directly in a GUI app
            var rlp = rlimit()
            
            // Try to raise RLIMIT_NOFILE (max number of open file descriptors)
            if getrlimit(RLIMIT_NOFILE, &rlp) == 0 {
                var newLimit = rlimit(rlim_cur: min(4096, rlp.rlim_max), rlim_max: rlp.rlim_max)
                setrlimit(RLIMIT_NOFILE, &newLimit)
            }
            
            // Try to raise RLIMIT_NPROC (max number of processes)
            if getrlimit(RLIMIT_NPROC, &rlp) == 0 {
                // Set soft limit to 75% of hard limit
                var newLimit = rlimit(rlim_cur: rlp.rlim_max * 3 / 4, rlim_max: rlp.rlim_max)
                setrlimit(RLIMIT_NPROC, &newLimit)
            }
            
            // Log the new limits
            var rlp_after = rlimit()
            if getrlimit(RLIMIT_NPROC, &rlp_after) == 0 {
                print("Process limit set to: \(rlp_after.rlim_cur) (soft) / \(rlp_after.rlim_max) (hard)")
            }
        }

    private func startMemoryMonitoring() {
            // Monitor more frequently
            memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) {
                [weak self] _ in
                self?.checkSystemResources()
            }
        }
        
        private func stopMemoryMonitoring() {
            memoryMonitorTimer?.invalidate()
            memoryMonitorTimer = nil
        }
        
        // Expanded to check more than just memory
        private func checkSystemResources() {
            // Check memory
            let memoryUsage = getCurrentMemoryUsage()
            
            // Check process count
            let processCount = ProcessManager.shared.getActiveProcessCount()
            let processorCount = ProcessInfo.processInfo.processorCount
            let processThreshold = Int(ProcessManager.shared.getUserProcessLimit() / 3)
                        
            
            // If any resource is over threshold, handle it
            if memoryUsage > memoryThreshold || processCount > processThreshold {
                handleResourceWarning()
            }
        }

    private func handleResourceWarning() {
            print("RESOURCE WARNING: Cleaning up resources")
            
            // Get diagnostics before cleanup
            let diagnostics = ProcessManager.shared.getSystemDiagnostics()
            print("RESOURCE WARNING DIAGNOSTICS:\n\(diagnostics)")
            
            // Clean up zombie processes
            ProcessManager.shared.cleanupZombieProcesses()
            
            // Force garbage collection if possible
            autoreleasepool {
                // This just creates an autorelease pool and immediately drains it
            }
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "System Resources Warning"
                alert.informativeText =
                    "The system is experiencing resource pressure. Some operations have been terminated to free up resources. Please wait a moment before trying again."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                
                if let window = NSApplication.shared.windows.first {
                    alert.beginSheetModal(for: window) { _ in }
                } else {
                    alert.runModal()
                }
            }
        }

    private func getCurrentMemoryUsage() -> Double {
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

            let used = active + inactive + speculative + wired + compressed - purgeable - external
            let free = totalSize - used
            return Double(used) / Double(totalSize)
        }

        return 0.0
    }
}
