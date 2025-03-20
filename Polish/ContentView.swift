//
//  ContentView.swift
//  Polish
//
//  Created by Andrew Jaffe on 3/19/25.
//

import SwiftUI

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let depth: Int
    let formattedSize: String
}

struct ContentView: View {
    @State private var outputText = ""
    @State private var isRunning = false
    @State private var foundFiles: [URL] = []
    @State private var fileItems: [FileItem] = []
    @State private var totalSizeText = ""
    @State private var scrollToBottom = false

    var body: some View {
        VStack(spacing: 20) {
            HeaderView()

            ButtonsView(
                isRunning: $isRunning,
                runBrewCleanup: runBrewCleanup,
                runPipCleanup: runPipCleanup,
                clearTrash: clearTrash,
                findFiles: findFiles

            )

            OutputView(
                fileItems: fileItems,
                totalSizeText: totalSizeText,
                outputText: outputText,
                scrollToBottom: $scrollToBottom
            )
        }
        .padding()
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")

            if let window = NSApplication.shared.windows.first {
                alert.beginSheetModal(for: window) { _ in }
            } else {
                alert.runModal()
            }
        }
    }

    func runPipCleanup() {
        self.isRunning = true
        Commands.runPipCommandForAllPythons(
            pipCommand: "cache purge",
            completion: { output in
                self.outputText = output
                self.isRunning = false
                self.scrollToBottom = true
            })
    }

    func clearTrash() {
        let trashPath = NSHomeDirectory() + "/.Trash"
        self.fileItems = []
        self.outputText = ""
        self.totalSizeText = ""
        self.isRunning = true

        var processedFiles = Set<String>()

        let basePath = trashPath
        let basePathComponents = basePath.components(separatedBy: "/")

        let totalSize = FindJunk.processFilesAndDirectories(at: trashPath) {
            url, isDirectory, size in

            let path = url.path
            if !processedFiles.contains(path) {
                processedFiles.insert(path)

                let pathComponents = path.components(separatedBy: "/")
                let relativeDepth = max(0, pathComponents.count - basePathComponents.count)

                let formattedSize = ByteCountFormatter.string(
                    fromByteCount: size, countStyle: .file)

                let fileItem = FileItem(
                    name: url.lastPathComponent,
                    path: path,
                    isDirectory: isDirectory,
                    size: size,
                    depth: relativeDepth,
                    formattedSize: formattedSize
                )

                DispatchQueue.main.async {
                    self.fileItems.append(fileItem)
                    self.scrollToBottom = true
                }

            }
        }

        DispatchQueue.main.async {
            if totalSize >= 0 {
                let formattedTotalSize = ByteCountFormatter.string(
                    fromByteCount: totalSize, countStyle: .file)
                self.totalSizeText = "Total size: \(formattedTotalSize) • All files processed"
            } else {
                self.totalSizeText = "Processing failed"
            }

            self.isRunning = false
            self.scrollToBottom = true
        }
    }

    func runBrewCleanup() {

        guard !isRunning else {
            showAlert(
                title: "Process Already Running",
                message: "Please wait for the current operation to complete.")
            return
        }

        isRunning = true
        fileItems = []
        outputText = ""

        Commands.runBrewCleanup { output in
            DispatchQueue.main.async {

                self.outputText = output

                self.scrollToBottom = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.scrollToBottom = true
                }

                if output.contains("All Homebrew operations completed.")
                    || output.contains("Error:")
                {
                    self.isRunning = false
                }
            }
        }
    }

    func findFiles() async {

        guard !isRunning else {
            showAlert(
                title: "Process Already Running",
                message: "Please wait for the current operation to complete.")
            return
        }

        isRunning = true
        outputText = outputText
        fileItems = []

        var outputBuffer = ""
        var lastScrollTime = Date()

        var files: [URL] = []
        files = await FindJunk.scanForUnneededFiles(
            maxFilesToScan: 1000,
            maxDepth: 5,
            progress: { item in

                var messageToAdd = ""

                if let message = item as? String {
                    messageToAdd = message + "\n"
                } else if let url = item as? URL {
                    messageToAdd = url.path + "\n"
                }

                if !messageToAdd.isEmpty {

                    outputBuffer += messageToAdd

                    let now = Date()
                    if now.timeIntervalSince(lastScrollTime) > 0.25 {

                        DispatchQueue.main.async {
                            self.outputText += outputBuffer
                            outputBuffer = ""
                            self.scrollToBottom = true
                            lastScrollTime = now
                        }
                    }
                }
            })

        DispatchQueue.main.async {
            self.outputText += outputBuffer
            self.outputText += "\nFile search completed. Found \(files.count) files.\n"
            self.isRunning = false
            self.scrollToBottom = true
        }
    }
}

struct HeaderView: View {
    var body: some View {
        Text("Cleanup Utility")
            .font(.title)
            .padding()
    }
}

struct ButtonsView: View {
    @Binding var isRunning: Bool
    let runBrewCleanup: () -> Void
    let runPipCleanup: () -> Void
    let clearTrash: () -> Void
    let findFiles: () async -> Void

    var body: some View {
        VStack(spacing: 15) {
            Button(action: clearTrash) {
                Text(isRunning ? "Running..." : "Process Files")
                    .frame(minWidth: 200)
                    .padding()
                    .background(isRunning ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isRunning)

            Button(action: runPipCleanup) {
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
        }
    }
}

struct OutputView: View {
    let fileItems: [FileItem]
    let totalSizeText: String
    let outputText: String
    @Binding var scrollToBottom: Bool

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !fileItems.isEmpty {
                        FileItemsView(
                            fileItems: fileItems,
                            totalSizeText: totalSizeText
                        )
                    } else {
                        TextOutputView(outputText: outputText)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 300)
            .background(Color(.systemGray))
            .cornerRadius(8)
            .onChange(of: scrollToBottom) {
                if scrollToBottom {
                    withAnimation {
                        scrollProxy.scrollTo(
                            fileItems.isEmpty ? "textBottom" : "bottom", anchor: .bottom)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom = false
                    }
                }
            }
            .onChange(of: fileItems.count) {
                scrollToBottom = true
            }
            .onChange(of: outputText) {
                scrollToBottom = true
            }
        }
        .padding()
    }
}

struct FileItemsView: View {
    let fileItems: [FileItem]
    let totalSizeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(fileItems) { item in
                FileItemRow(item: item)
            }

            if !totalSizeText.isEmpty {
                Text(totalSizeText)
                    .font(.headline)
                    .padding(.top, 8)
                    .id("bottom")
            }
        }
    }
}

struct FileItemRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 4) {

            ForEach(0..<(item.depth - 1), id: \.self) { _ in
                Spacer()
                    .frame(width: 20)
            }

            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundColor(item.isDirectory ? .blue : .gray)

            Text(item.name)
                .foregroundColor(.primary)

            Spacer()

            if !item.isDirectory {
                Text(item.formattedSize)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

struct TextOutputView: View {
    let outputText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(outputText)
                .font(.system(.body, design: .monospaced))
                .lineLimit(nil)

            Color.clear
                .frame(height: 1)
                .id("textBottom")
        }
    }
}

#Preview {
    ContentView()
}
