//
//  ContentView.swift
//  Polish
//
//  Created by Andrew Jaffe on 3/19/25.
//

import SwiftUI

struct ContentView: View {
    @State private var outputText = ""
    @State private var isRunning = false
    @State private var foundFiles: [URL] = []
    @State private var scrollPosition: UUID = UUID()

    var body: some View {
        VStack(spacing: 20) {
            Text("Cleanup Utility")
                .font(.title)
                .padding()

            Button(action: {
                runBrewCleanup()
            }) {
                Text(isRunning ? "Running..." : "Run Brew Cleanup")
                    .frame(minWidth: 200)
                    .padding()
                    .background(isRunning ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isRunning)

            Button(action: {
                self.isRunning = true
                Commands.runPipCommandForAllPythons(
                    pipCommand: "cache purge",
                    completion: { output in
                        self.outputText = output
                        self.isRunning = false
                    })
            }) {
                Text(isRunning ? "Searching..." : "Clear Python Cache")
                    .frame(minWidth: 200)
                    .padding()
                    .background(isRunning ? Color.gray : Color.yellow)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isRunning)

            Button(action: {
                Task {
                    await findFiles()
                }
            }) {
                Text(isRunning ? "Searching..." : "Find Files")
                    .frame(minWidth: 200)
                    .padding()
                    .background(isRunning ? Color.gray : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isRunning)

            Button(action: {
                clearTrash()
            }) {
                Text(isRunning ? "Running..." : "Empty Trash")
                    .frame(minWidth: 200)
                    .padding()
                    .background(isRunning ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isRunning)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading) {
                        Text(outputText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // This is our anchor point that we'll scroll to
                        Text("")
                            .id(scrollPosition)
                            .frame(height: 1)
                    }
                    .padding()
                    .background(Color(.systemGray))
                    .cornerRadius(8)
                    .foregroundStyle(.black)
                }
                .frame(height: 300)
                .padding()
                .onChange(of: scrollPosition) {
                    withAnimation {
                        scrollProxy.scrollTo(scrollPosition)
                    }
                }
            }
        }
        .padding()
    }

    func runBrewCleanup() {
        isRunning = true

        Commands.runBrewCleanup { output in
            self.outputText = output
            self.isRunning = false
            self.scrollPosition = UUID()  // Generate new ID to trigger scroll
        }
    }

    func findFiles() async {
        isRunning = true
        outputText = ""

        // Create a buffer for collecting output before displaying
        var outputBuffer = ""
        var lastScrollTime = Date()

        var files: [URL] = []
        files = await FindJunk.scanForUnneededFiles(progress: { item in
            // Handle both String and URL types
            var messageToAdd = ""

            if let message = item as? String {
                messageToAdd = message + "\n"
            } else if let url = item as? URL {
                messageToAdd = url.path + "\n"
            }

            if !messageToAdd.isEmpty {
                // Add to buffer
                outputBuffer += messageToAdd

                // Throttle UI updates to prevent too many per frame
                let now = Date()
                if now.timeIntervalSince(lastScrollTime) > 0.1 {  // Update UI at most every 100ms
                    // Update on main thread
                    DispatchQueue.main.async {
                        self.outputText += outputBuffer
                        outputBuffer = ""
                        self.scrollPosition = UUID()
                        lastScrollTime = now
                    }
                }
            }
        })

        // Final update with any remaining buffered text
        DispatchQueue.main.async {
            self.outputText += outputBuffer
            self.outputText += "\nFile search completed. Found \(files.count) files.\n"
            self.isRunning = false
            self.scrollPosition = UUID()
        }
    }

    func clearTrash() {
        let trashPath = NSHomeDirectory() + "/.Trash/"
        self.outputText = ""
        self.isRunning = true

        // Keep track of files being processed to avoid duplicates
        var processedFiles = Set<String>()

        // Keep track of the base path length to calculate indentation
        let basePath = trashPath
        let basePathComponents = basePath.components(separatedBy: "/")

        let totalSize = FindJunk.processFilesAndDirectories(at: trashPath) {
            url, isDirectory, size in

            // Print file/directory information - only once per file
            let path = url.path
            if !processedFiles.contains(path) {
                processedFiles.insert(path)

                // Calculate indentation based on directory depth relative to the base path
                let pathComponents = path.components(separatedBy: "/")
                let relativeDepth = max(0, pathComponents.count - basePathComponents.count)
                let indentation = String(repeating: "    ", count: relativeDepth)

                if isDirectory {
                    self.outputText += "\(indentation)Directory: \(url.lastPathComponent)\n"
                } else {
                    let formattedSize = ByteCountFormatter.string(
                        fromByteCount: size, countStyle: .file)
                    self.outputText +=
                        "\(indentation)File: \(url.lastPathComponent), Size: \(formattedSize)\n"
                }

                // Update scrolling after each file is listed
                self.scrollPosition = UUID()

                Commands.removeFileOrDirectory(path: url.path) { _ in

                }
            }
        }

        // Add the total size summary
        if totalSize >= 0 {
            let formattedTotalSize = ByteCountFormatter.string(
                fromByteCount: totalSize, countStyle: .file)
            self.outputText += "\nTrash emptied. Cleared \(formattedTotalSize) of space\n"
        } else {
            self.outputText += "\nProcessing failed\n"
        }

        self.isRunning = false
        self.scrollPosition = UUID()

    }
}

#Preview {
    ContentView()
}
