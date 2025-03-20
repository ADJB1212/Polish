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

        // Check if the path exists
        guard FileManager.default.fileExists(atPath: decodedPath, isDirectory: &isDir) else {
            return .notFound
        }

        return isDir.boolValue ? .directory : .file
    }

    static func escapePathForShell(_ path: String) -> String {
        // First decode any percent-encoded characters
        let decodedPath = path.removingPercentEncoding ?? path

        // Handle empty paths
        if decodedPath.isEmpty {
            return "\"\""
        }

        // Check if the path needs escaping at all
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

        // Option 1: Use macOS/Unix style with backslash escaping
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
