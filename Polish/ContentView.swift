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

            ScrollView {
                Text(outputText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray))
                    .cornerRadius(8)
                    .foregroundStyle(.black)
            }
            .frame(height: 300)
            .padding()
        }
        .padding()
    }

    func runBrewCleanup() {
        isRunning = true

        Commands.runBrewCleanup { output in
            self.outputText = output
            self.isRunning = false
        }
    }

    func findFiles() async {
        isRunning = true
        outputText = ""

        var files: [URL] = []
            files = await FindJunk.scanForUnneededFiles(progress: { fileURL in
                DispatchQueue.main.async {
                    //self.outputText += fileURL.path + "\n"
                }
            })
            
            DispatchQueue.main.async {
                self.outputText += "\nFile search completed. Found \(files.count) files.\n"
                self.isRunning = false
            }
    }

}

#Preview {
    ContentView()
}
