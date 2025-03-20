//
//  FindJunk.swift
//  Polish
//
//  Created by Andrew Jaffe on 3/19/25.
//

import Foundation
import SwiftUI

class FindJunk {

    static func scanForUnneededFiles(progress: @escaping (Any) -> Void) async -> [URL] {

        let cacheDirectories: [String] = [
            NSHomeDirectory() + "/Library/Caches",
            "/tmp",
            "/private/tmp",
        ]

        var results: [URL] = []
        let fileManager = FileManager.default

        for dirPath in cacheDirectories {
            let dirURL = URL(fileURLWithPath: dirPath)

            // Report the top-level cache directory
            let topSize = calculateDirectorySize(dirURL)
            progress(dirURL)

            // Get only the direct subdirectories (1 level deep)
            if let contents = try? fileManager.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
            {
                for fileURL in contents {
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
                        if isDir.boolValue {
                            // Calculate size and report progress only for directories one level deep
                            let size = calculateDirectorySize(fileURL)
                            progress(fileURL)
                        }

                        // Continue adding all files to results for potential cleanup
                        if !isDir.boolValue {
                            results.append(fileURL)
                        }
                    }
                }
            }

            // Now collect all files recursively for results
            if let enumerator = fileManager.enumerator(
                at: dirURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
                errorHandler: { (_, _) -> Bool in
                    true
                })
            {
                for case let fileURL as URL in enumerator {
                    if isFile(fileURL) {
                        results.append(fileURL)
                    }
                }
            }
        }

        // Handle Application Support directory similarly
        let applicationSupportDir = NSHomeDirectory() + "/Library/Application Support"
        let appSupportURL = URL(fileURLWithPath: applicationSupportDir)

        // Report the Application Support directory
        let appSupportSize = calculateDirectorySize(appSupportURL)
        if isLikelyLeftover(appSupportURL) {
            progress(appSupportURL)
        }

        // Report only direct subdirectories that are likely leftovers (1 level deep)
        if let contents = try? fileManager.contentsOfDirectory(
            at: appSupportURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        {
            for fileURL in contents {
                if isLikelyLeftover(fileURL) {
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
                        if isDir.boolValue {
                            // Calculate size and report progress only for directories one level deep
                            let size = calculateDirectorySize(fileURL)
                            progress(fileURL)
                        }

                        // Add to results
                        results.append(fileURL)
                    }
                }
            }
        }

        // Calculate and report the total size at the end
        let totalSize = results.reduce(Int64(0)) { total, url in
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? Int64 {
                    return total + fileSize
                }
            } catch {
                // Ignore errors
            }
            return total
        }

        progress("Total size of all files: \(formatFileSize(totalSize))")

        return results
    }

    static func calculateDirectorySize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil)
        {
            for case let fileURL as URL in enumerator {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        totalSize += fileSize
                    }
                } catch {
                    print("calc fail")
                }
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
        FileManager.default
            .fileExists(atPath: url.path, isDirectory: &isDirectory)
        return !isDirectory.boolValue
    }

    static func findPotentialLeftovers(in path: String) -> [URL] {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: path)
        var results: [URL] = []
        guard
            let contents = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])
        else { return [] }

        for url in contents {
            if FindJunk.isLikelyLeftover(url) {
                results.append(url)
            }
        }

        return results
    }

    static func isLikelyLeftover(_ url: URL) -> Bool {
        let installedAppNames = getInstalledApplications()
        let baseName = url.deletingPathExtension().lastPathComponent
        return !installedAppNames.contains(baseName)
    }

    static func getInstalledApplications() -> Set<String> {
        var allAppNames = [String]()
        let fileManager = FileManager.default

        let applicationDirs = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            "/System/Applications",
        ]

        for dir in applicationDirs {
            // Get apps in the top level directory
            let topLevelApps = (try? fileManager.contentsOfDirectory(atPath: dir)) ?? []

            for item in topLevelApps {
                let fullPath = "\(dir)/\(item)"

                // Add top-level apps
                if item.hasSuffix(".app") {
                    let name = item.replacingOccurrences(of: ".app", with: "")
                    allAppNames.append(name)
                }

                // Check if this is a directory and not an app bundle
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir),
                    isDir.boolValue && !item.hasSuffix(".app")
                {
                    // Look for app bundles within this subdirectory
                    if let subItems = try? fileManager.contentsOfDirectory(atPath: fullPath) {
                        for subItem in subItems where subItem.hasSuffix(".app") {
                            let name = subItem.replacingOccurrences(of: ".app", with: "")
                            allAppNames.append(name)
                        }
                    }
                }
            }
        }

        return Set(allAppNames)
    }

}
