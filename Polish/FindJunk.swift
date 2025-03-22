//
//  FindJunk.swift
//  Polish
//
//  Created by Andrew Jaffe on 3/19/25.
//

import Darwin
import Foundation
import SwiftUI

class FindJunk {
    static func scanForUnneededFiles(
        maxFilesToScan: Int = 1000, maxDepth: Int = 8, progress: @escaping (Any) -> Void
    ) async -> [URL] {

        if !Commands.checkSystemResources() {
            progress("System resources are low. Operation aborted.")
            return []
        }

        let directoriesWithJunk: [String] = [
            NSHomeDirectory() + "/Library/logs", "/Library/logs", "/var/log", NSHomeDirectory() + "/Library/Developer/Xcode/iOS\\ Device\\ Logs", NSHomeDirectory() + "/Library/Containers/*/Data/Library/Logs", NSHomeDirectory() + "/Library/Developer/Xcode/Archives", NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
        ]

        var results: [URL] = []
        let fileManager = FileManager.default
        var scannedFileCount = 0

        await withTaskGroup(of: [URL].self) { group in
            for dirPath in directoriesWithJunk {
                
                let dirURL = URL(fileURLWithPath: dirPath)

                group.addTask {
                    return await scanDirectory(
                        dirURL, maxDepth: maxDepth, maxFiles: maxFilesToScan, progress: progress
                    )
                }
            }

            for await directoryResults in group {
                results.append(contentsOf: directoryResults)

                scannedFileCount += directoryResults.count
                if scannedFileCount >= maxFilesToScan {
                    progress("Reached file scan limit of \(maxFilesToScan). Stopping scan.")
                    group.cancelAll()
                    break
                }
            }
        }

        let totalSize = results.reduce(Int64(0)) { total, url in
            if isFile(url) {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    if let fileSize = attributes[.size] as? Int64 { return total + fileSize }
                } catch {

                }
            } else {

                return total + estimateDirectorySize(url, maxDepth: 2)
            }
            return total
        }

        progress("Total size of all files: \(formatFileSize(totalSize))")

        return results.prefix(maxFilesToScan).map { $0 }
    }

    private static func scanDirectory(
        _ dirURL: URL, maxDepth: Int, maxFiles: Int, progress: @escaping (Any) -> Void
    ) async -> [URL] {
        var results: [URL] = []
        let fileManager = FileManager.default

        var directoriesToScan = [(url: dirURL, depth: 0)]
        var scannedCount = 0

        while !directoriesToScan.isEmpty && scannedCount < maxFiles {

            let (currentDir, depth) = directoriesToScan.removeFirst()

            if depth > maxDepth { continue }

            guard
                let contentsURLs = try? fileManager.contentsOfDirectory(
                    at: currentDir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles])
            else { continue }

            for url in contentsURLs {

                if scannedCount >= maxFiles { break }

                do {
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                    let isDirectory = resourceValues.isDirectory ?? false

                    if isDirectory {

                        if depth < maxDepth {
                            directoriesToScan.append((url: url, depth: depth + 1))

                            if depth <= 1 { progress(url) }
                        }
                    } else {

                        results.append(url)
                        scannedCount += 1

                        if depth <= 1 && scannedCount % 5 == 0 { progress(url) }
                    }
                } catch {

                    continue
                }

                if scannedCount % 20 == 0 { await Task.yield() }
            }
        }

        return results
    }

    static func estimateDirectorySize(_ url: URL, maxDepth: Int = 2) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        var currentDepth = 0
        var scannedItems = 0
        let maxItems = 100

        var directoriesToScan = [(url, 0)]

        while !directoriesToScan.isEmpty && scannedItems < maxItems {
            let (currentDir, depth) = directoriesToScan.removeFirst()

            if depth > maxDepth { continue }

            guard
                let contents = try? fileManager.contentsOfDirectory(
                    at: currentDir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles])
            else { continue }

            let samplesToTake = min(contents.count, 20)
            let sampleInterval = max(1, contents.count / samplesToTake)

            for i in stride(from: 0, to: contents.count, by: sampleInterval) {
                if scannedItems >= maxItems { break }

                if i < contents.count {
                    let fileURL = contents[i]

                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [
                            .isDirectoryKey, .fileSizeKey,
                        ])

                        if resourceValues.isDirectory ?? false {
                            if depth < maxDepth { directoriesToScan.append((fileURL, depth + 1)) }
                        } else if let fileSize = resourceValues.fileSize {
                            totalSize += Int64(fileSize)
                        }

                        scannedItems += 1
                    } catch {

                        continue
                    }
                }
            }
        }

        if directoriesToScan.isEmpty && scannedItems < maxItems {

            return totalSize
        } else {

            let estimationFactor = 5.0
            return Int64(Double(totalSize) * estimationFactor)
        }
    }

    static func calculateDirectorySize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        var filesScanned = 0
        let maxFilesToScan = 1000

        if let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles],
            errorHandler: nil)
        {
            for case let fileURL as URL in enumerator {

                filesScanned += 1
                if filesScanned > maxFilesToScan { break }

                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    if let fileSize = attributes[.size] as? Int64 { totalSize += fileSize }
                } catch {

                }

                if filesScanned % 100 == 0 { Thread.sleep(forTimeInterval: 0.001) }
            }
        }

        return totalSize
    }

    static func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    static func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    static func findPotentialLeftovers(in path: String, maxItems: Int = 100) -> [URL] {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: path)
        var results: [URL] = []
        var itemsProcessed = 0

        guard
            let contents = try? fm.contentsOfDirectory(
                at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }

        for url in contents {
            if itemsProcessed >= maxItems { break }

            if FindJunk.isLikelyLeftover(url) {
                results.append(url)
                itemsProcessed += 1
            }
        }

        return results
    }

    static func isLikelyLeftover(_ url: URL) -> Bool {

        struct StaticAppNames {
            static var installedApps: Set<String>?
            static var lastUpdate = Date(timeIntervalSince1970: 0)
            static let cacheDuration: TimeInterval = 300

            static func getInstalledApps() -> Set<String> {
                let now = Date()

                if let apps = installedApps, now.timeIntervalSince(lastUpdate) < cacheDuration {
                    return apps
                }

                installedApps = FindJunk.getInstalledApplications()
                lastUpdate = now
                return installedApps ?? []
            }
        }

        let installedAppNames = StaticAppNames.getInstalledApps()
        let baseName = url.deletingPathExtension().lastPathComponent
        return !installedAppNames.contains(baseName)
    }

    static func getInstalledApplications() -> Set<String> {
        var allAppNames = [String]()
        let fileManager = FileManager.default

        let applicationDirs = [
            "/Applications", NSHomeDirectory() + "/Applications", "/System/Applications",
        ]

        for dir in applicationDirs {

            var isDir: ObjCBool = false
            if !fileManager.fileExists(atPath: dir, isDirectory: &isDir) || !isDir.boolValue {
                continue
            }

            guard let topLevelApps = try? fileManager.contentsOfDirectory(atPath: dir) else {
                continue
            }

            var appCount = 0
            for item in topLevelApps {

                if appCount > 100 { break }

                let fullPath = "\(dir)/\(item)"

                if item.hasSuffix(".app") {
                    let name = item.replacingOccurrences(of: ".app", with: "")
                    allAppNames.append(name)
                    appCount += 1
                }

                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir),
                    isDir.boolValue && !item.hasSuffix(".app")
                {

                    if let subItems = try? fileManager.contentsOfDirectory(atPath: fullPath) {
                        for subItem in subItems where subItem.hasSuffix(".app") {
                            let name = subItem.replacingOccurrences(of: ".app", with: "")
                            allAppNames.append(name)
                            appCount += 1

                            if appCount > 100 { break }
                        }
                    }
                }
            }
        }

        return Set(allAppNames)
    }

    static func processFilesAndDirectories(at path: String, skipHiddenFiles: Bool, handler: (URL, Bool, Int64, Int) -> Void)
        -> Int64
    {
        let fileManager = FileManager.default
        let path = Helper.escapePathForShell(path)
        let url = URL(fileURLWithPath: path)
        var totalSize: Int64 = 0
        var processedCount = 0
        let maxItemsToProcess = 20000

        guard fileManager.fileExists(atPath: path) else {
            print("Path does not exist: \(path)")
            return -1
        }
        var options: FileManager.DirectoryEnumerationOptions = FileManager.DirectoryEnumerationOptions.init()
        if(skipHiddenFiles){
            options = .skipsHiddenFiles
        }

        guard
            let enumerator = fileManager.enumerator(
                at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [options],
                errorHandler: { (url, error) -> Bool in
                    print("Error accessing \(url): \(error)")
                    return true
                })
        else {
            print("Failed to create directory enumerator for \(path)")
            return -1
        }

        for case let itemURL as URL in enumerator {

            processedCount += 1
            if processedCount > maxItemsToProcess {
                print("Reached maximum processing limit of \(maxItemsToProcess) items")
                break
            }

            do {
                let resourceValues = try itemURL.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey,
                ])
                let isDirectory = resourceValues.isDirectory ?? false

                var fileSize: Int64 = 0
                if !isDirectory, let size = resourceValues.fileSize {
                    fileSize = Int64(size)
                    totalSize += fileSize
                }
                else if (isDirectory){
                    fileSize=Int64(calculateDirectorySize(itemURL))
                }
                let basePath = path
                let basePathComponents = basePath.components(separatedBy: "/")
                let pathComponents = path.components(separatedBy: "/")
                let relativeDepth = max(0, pathComponents.count - basePathComponents.count)

                handler(itemURL, isDirectory, fileSize, relativeDepth)

                if processedCount % 100 == 0 { Thread.sleep(forTimeInterval: 0.001) }
            } catch { print("Error reading resource values for \(itemURL): \(error)") }
        }

        return totalSize
    }
}
