//
//  Helper.swift
//  Polish
//
//  Created by Andrew Jaffe on 3/20/25.
//

import Foundation
import SwiftUI

class Helper {

    enum PathType {
        case directory
        case file
        case notFound
    }

    static func getPathType(_ path: String) -> PathType {
        var isDir: ObjCBool = false
        let decodedPath: String
        if let decoded = path.removingPercentEncoding {
            decodedPath = decoded
        } else {
            decodedPath = path
        }

        guard FileManager.default.fileExists(atPath: decodedPath, isDirectory: &isDir) else {
            return .notFound
        }

        return isDir.boolValue ? .directory : .file
    }

    static func escapePathForShell(_ path: String) -> String {

        let decodedPath = path.removingPercentEncoding ?? path

        if decodedPath.isEmpty {
            return "\"\""
        }

        let needsEscaping =
            decodedPath.contains(" ") || decodedPath.contains("(") || decodedPath.contains(")")
            || decodedPath.contains("'") || decodedPath.contains("\"") || decodedPath.contains("&")
            || decodedPath.contains(";") || decodedPath.contains("<") || decodedPath.contains(">")
            || decodedPath.contains("|") || decodedPath.contains("*") || decodedPath.contains("?")
            || decodedPath.contains("[") || decodedPath.contains("]") || decodedPath.contains("$")
            || decodedPath.contains("`") || decodedPath.contains("\\") || decodedPath.contains("!")
            || decodedPath.contains("#") || decodedPath.contains("~")

        if !needsEscaping {
            return decodedPath
        }

        var escapedPath = ""
        for character in decodedPath {
            if " ()[]&;$\\'\"`<>|*?!#~".contains(character) {
                escapedPath.append("\\")
            }
            escapedPath.append(character)
        }

        return escapedPath
    }

}

public enum DataSizeBase: String {
    case bit
    case byte
}

public struct Units {
    public let bytes: Int64

    public init(bytes: Int64) {
        self.bytes = bytes
    }

    public var kilobytes: Double {
        return Double(bytes) / 1_000
    }
    public var megabytes: Double {
        return kilobytes / 1_000
    }
    public var gigabytes: Double {
        return megabytes / 1_000
    }
    public var terabytes: Double {
        return gigabytes / 1_000
    }

    public func getReadableTuple(base: DataSizeBase = .byte) -> (String, String) {
        let stringBase = base == .byte ? "B" : "b"
        let multiplier: Double = base == .byte ? 1 : 8

        switch bytes {
        case 0..<1_000:
            return ("0", "K\(stringBase)/s")
        case 1_000..<(1_000 * 1_000):
            return (String(format: "%.0f", kilobytes * multiplier), "K\(stringBase)/s")
        case 1_000..<(1_000 * 1_000 * 100):
            return (String(format: "%.1f", megabytes * multiplier), "M\(stringBase)/s")
        case (1_000 * 1_000 * 100)..<(1_000 * 1_000 * 1_000):
            return (String(format: "%.0f", megabytes * multiplier), "M\(stringBase)/s")
        case (1_000 * 1_000 * 1_000)...Int64.max:
            return (String(format: "%.1f", gigabytes * multiplier), "G\(stringBase)/s")
        default:
            return (String(format: "%.0f", kilobytes * multiplier), "K\(stringBase)B/s")
        }
    }

    public func getReadableSpeed(base: DataSizeBase = .byte, omitUnits: Bool = false) -> String {
        let stringBase = base == .byte ? "B" : "b"
        let multiplier: Double = base == .byte ? 1 : 8

        switch bytes * Int64(multiplier) {
        case 0..<1_000:
            let unit = omitUnits ? "" : " K\(stringBase)/s"
            return "0\(unit)"
        case 1_000..<(1_000 * 1_000):
            let unit = omitUnits ? "" : " K\(stringBase)/s"
            return String(format: "%.0f\(unit)", kilobytes * multiplier)
        case 1_000..<(1_000 * 1_000 * 100):
            let unit = omitUnits ? "" : " M\(stringBase)/s"
            return String(format: "%.1f\(unit)", megabytes * multiplier)
        case (1_000 * 1_000 * 100)..<(1_000 * 1_000 * 1_000):
            let unit = omitUnits ? "" : " M\(stringBase)/s"
            return String(format: "%.0f\(unit)", megabytes * multiplier)
        case (1_000 * 1_000 * 1_000)...Int64.max:
            let unit = omitUnits ? "" : " G\(stringBase)/s"
            return String(format: "%.1f\(unit)", gigabytes * multiplier)
        default:
            let unit = omitUnits ? "" : " K\(stringBase)/s"
            return String(format: "%.0f\(unit)", kilobytes * multiplier)
        }
    }

    public func getReadableMemory(style: ByteCountFormatter.CountStyle = .file) -> String {
        let formatter: ByteCountFormatter = ByteCountFormatter()
        formatter.countStyle = style
        formatter.includesUnit = true
        formatter.isAdaptive = true

        var value = formatter.string(fromByteCount: Int64(self.bytes))
        if let idx = value.lastIndex(of: ",") {
            value.replaceSubrange(idx...idx, with: ".")
        }

        return value
    }

    public func toUnit(_ unit: SizeUnit) -> Double {
        switch unit {
        case .KB: return self.kilobytes
        case .MB: return self.megabytes
        case .GB: return self.gigabytes
        case .TB: return self.terabytes
        default: return Double(self.bytes)
        }
    }
}

public protocol KeyValue_p {
    var key: String { get }
    var value: String { get }
}

public struct SizeUnit: KeyValue_p, Equatable {
    public let key: String
    public let value: String

    public static func == (lhs: SizeUnit, rhs: SizeUnit) -> Bool {
        return lhs.key == rhs.key
    }
}

extension SizeUnit: CaseIterable {
    public static var byte: SizeUnit { return SizeUnit(key: "byte", value: "Bytes") }
    public static var KB: SizeUnit { return SizeUnit(key: "KB", value: "KB") }
    public static var MB: SizeUnit { return SizeUnit(key: "MB", value: "MB") }
    public static var GB: SizeUnit { return SizeUnit(key: "GB", value: "GB") }
    public static var TB: SizeUnit { return SizeUnit(key: "TB", value: "TB") }

    public static var allCases: [SizeUnit] {
        [.byte, .KB, .MB, .GB, .TB]
    }

    public static func fromString(_ key: String, defaultValue: SizeUnit = .byte) -> SizeUnit {
        return SizeUnit.allCases.first { $0.key == key } ?? defaultValue
    }

    public func toBytes(_ value: Int) -> Int {
        switch self {
        case .KB:
            return value * 1_000
        case .MB:
            return value * 1_000 * 1_000
        case .GB:
            return value * 1_000 * 1_000 * 1_000
        case .TB:
            return value * 1_000 * 1_000 * 1_000 * 1_000
        default:
            return value
        }
    }
}

public struct ProcessorUsage {
    public var user: Double
    public var system: Double
    public var idle: Double
    public var nice: Double
}

private let HOST_CPU_LOAD_INFO_COUNT: mach_msg_type_number_t = UInt32(
    MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

public class CPU: NSObject {
    static let machHost = mach_host_self()
    static var hostCPULoadInfo: host_cpu_load_info {
        var size = HOST_CPU_LOAD_INFO_COUNT
        var hostInfo = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &hostInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(machHost, HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        #if DEBUG
            if result != KERN_SUCCESS {
                fatalError(
                    "ERROR - \(#file):\(#function) - kern_result_t = "
                        + "\(result)")
            }
        #endif

        return hostInfo
    }

    private static var loadPrevious = host_cpu_load_info()

    public static func systemUsage() -> ProcessorUsage {
        let load = self.hostCPULoadInfo

        let userDiff = Double(load.cpu_ticks.0 - loadPrevious.cpu_ticks.0)
        let sysDiff = Double(load.cpu_ticks.1 - loadPrevious.cpu_ticks.1)
        let idleDiff = Double(load.cpu_ticks.2 - loadPrevious.cpu_ticks.2)
        let niceDiff = Double(load.cpu_ticks.3 - loadPrevious.cpu_ticks.3)

        let totalTicks = sysDiff + userDiff + niceDiff + idleDiff

        let sys = sysDiff / totalTicks * 100.0
        let user = userDiff / totalTicks * 100.0
        let idle = idleDiff / totalTicks * 100.0
        let nice = niceDiff / totalTicks * 100.0

        loadPrevious = load

        return ProcessorUsage(user: user, system: sys, idle: idle, nice: nice)
    }

    public static func appUsage() -> Float {
        var result: Int32
        var threadList = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        var threadCount = UInt32(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        var threadInfo = thread_basic_info()

        result = withUnsafeMutablePointer(to: &threadList) {
            $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadCount)
            }
        }

        if result != KERN_SUCCESS { return 0 }

        return (0..<Int(threadCount))
            .compactMap { index -> Float? in
                var threadInfoCount = UInt32(THREAD_INFO_MAX)
                result = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(
                            threadList[index], UInt32(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                if result != KERN_SUCCESS { return nil }
                let isIdle = threadInfo.flags == TH_FLAGS_IDLE

                return !isIdle ? (Float(threadInfo.cpu_usage) / Float(TH_USAGE_SCALE)) * 100 : nil
            }
            .reduce(0, +)
    }

    private static var processorPrevious: processor_info_array_t?

    public static func coreUsage() -> [ProcessorUsage] {
        var cpuCount: natural_t = 0
        var cpuInfoArray: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        guard
            KERN_SUCCESS
                == host_processor_info(
                    mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &cpuInfoArray,
                    &cpuInfoCount)
        else {
            return [ProcessorUsage]()
        }

        do {
            guard cpuCount > 0 else {
                return [ProcessorUsage]()
            }

            guard let cpuInfoArray = cpuInfoArray else {
                return [ProcessorUsage]()
            }

            defer {
                vm_deallocate(
                    mach_task_self_, vm_address_t(cpuInfoArray.pointee), vm_size_t(cpuInfoCount))
            }

            var array = [ProcessorUsage]()
            for i in 0..<cpuCount {
                let index = Int32(i) * CPU_STATE_MAX

                let userTick = UInt32(cpuInfoArray[Int(index + CPU_STATE_USER)])
                let systemTick = UInt32(cpuInfoArray[Int(index + CPU_STATE_SYSTEM)])
                let idleTick = UInt32(cpuInfoArray[Int(index + CPU_STATE_IDLE)])
                let niceTick = UInt32(cpuInfoArray[Int(index + CPU_STATE_NICE)])

                let user: Double
                let system: Double
                let idle: Double
                let nice: Double

                if let processorPrevious = processorPrevious {
                    let userDiff = userTick - UInt32(processorPrevious[Int(index + CPU_STATE_USER)])
                    let systemDiff =
                        systemTick - UInt32(processorPrevious[Int(index + CPU_STATE_SYSTEM)])
                    let idleDiff = idleTick - UInt32(processorPrevious[Int(index + CPU_STATE_IDLE)])
                    let niceDiff = niceTick - UInt32(processorPrevious[Int(index + CPU_STATE_NICE)])

                    let totalDiff = userDiff + systemDiff + idleDiff + niceDiff

                    user = Double(userDiff) / Double(totalDiff) * 100.0
                    system = Double(systemDiff) / Double(totalDiff) * 100.0
                    idle = Double(idleDiff) / Double(totalDiff) * 100.0
                    nice = Double(niceDiff) / Double(totalDiff) * 100.0

                } else {

                    let totalTick = userTick + systemTick + idleTick + niceTick

                    user = Double(userTick) / Double(totalTick) * 100.0
                    system = Double(systemTick) / Double(totalTick) * 100.0
                    idle = Double(idleTick) / Double(totalTick) * 100.0
                    nice = Double(niceTick) / Double(totalTick) * 100.0
                }

                let usage = ProcessorUsage(user: user, system: system, idle: idle, nice: nice)

                array.append(usage)
            }

            processorPrevious = cpuInfoArray

            return array
        }
    }
}
