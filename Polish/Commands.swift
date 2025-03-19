//
//  Commands.swift
//  Polish
//
//  Created by Andrew Jaffe on 3/19/25.
//

import Foundation

class Commands {
    static func runBrewCleanup(completion: @escaping (String) -> Void) {
        runCommand(
            command: "PATH=$PATH:/usr/local/bin:/opt/homebrew/bin brew cleanup && brew autoremove",
            completion: completion)
    }
    

    private static func runCommand(command: String, completion: @escaping (String) -> Void) {
        var outputText = "Running command: \(command)\n"

        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.standardError = pipe

        let outHandle = pipe.fileHandleForReading

        outHandle.readabilityHandler = { fileHandle in
            if let line = String(data: fileHandle.availableData, encoding: .utf8) {
                DispatchQueue.main.async {
                    outputText += line
                    completion(outputText)
                }
            }
        }
        do {
            try task.run()

            DispatchQueue.global(qos: .background).async {
                task.waitUntilExit()

                DispatchQueue.main.async {
                    outputText += "\nFinished with exit code: \(task.terminationStatus)"
                    outHandle.readabilityHandler = nil
                    completion(outputText)
                }
            }
        } catch {
            DispatchQueue.main.async {
                outputText += "\nError: \(error.localizedDescription)"
                completion(outputText)
            }
        }
    }
}
