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
    private let memoryThreshold: Double = 0.90

    func applicationDidFinishLaunching(_ notification: Notification) {

        startMemoryMonitoring()

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MemoryWarning"), object: nil, queue: .main
        ) { [weak self] _ in self?.handleMemoryWarning() }
    }

    func applicationWillTerminate(_ notification: Notification) {

        ProcessManager.shared.terminateAllProcesses()

        stopMemoryMonitoring()

        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func startMemoryMonitoring() {
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] _ in self?.checkMemoryUsage()
        }
    }

    private func stopMemoryMonitoring() {
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
    }

    private func checkMemoryUsage() {
        let memoryUsage = getCurrentMemoryUsage()
        if memoryUsage > memoryThreshold { handleMemoryWarning() }
    }

    private func handleMemoryWarning() {

        ProcessManager.shared.terminateAllProcesses()

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Memory Warning"
            alert.informativeText =
                "The system is experiencing memory pressure. Some operations have been terminated to free up resources."
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
            let swapins = Int64(stats.swapins)
            let swapouts = Int64(stats.swapouts)

            let used = active + inactive + speculative + wired + compressed - purgeable - external
            let free = totalSize - used
            return Double(totalSize - free) / Double(totalSize)
        }

        return 0.0
    }
}
