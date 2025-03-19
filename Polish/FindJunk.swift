//
//  FindJunk.swift
//  Polish
//
//  Created by Andrew Jaffe on 3/19/25.
//

import Foundation
import SwiftUI

class FindJunk {

    static func scanForUnneededFiles(progress: @escaping (URL) -> Void) async -> [URL] {

        let cacheDirectories: [String] = [
            NSHomeDirectory() + "/Library/Caches",
            "/tmp",
            "/private/tmp",
        ]

        var results: [URL] = []
        let fileManager = FileManager.default

        for dirPath in cacheDirectories {
            let dirURL = URL(fileURLWithPath: dirPath)
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
                        progress(fileURL)
                    }
                }
            }
        }

        let applicationSupportDir = NSHomeDirectory() + "/Library/Application Support"
        let leftoverFiles = findPotentialLeftovers(in: applicationSupportDir)
        for fileURL in leftoverFiles {
            results.append(fileURL)
            progress(fileURL)
        }
        return results
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
        guard let contents = try? fm.contentsOfDirectory(
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
            let apps = (try? fileManager.contentsOfDirectory(atPath: dir)) ?? []

            for app in apps where app.hasSuffix(".app") {
                let name = app.replacingOccurrences(of: ".app", with: "")
                allAppNames.append(name)
            }
        }
        return Set(allAppNames)
    }

}
