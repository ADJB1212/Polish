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

    var body: some View {
        VStack(spacing: 20) {
            Text("Cleanup Utility")
                .font(.title)
                .padding()

            Button(action: {
                runBrewCleanup()
            }) {
                Text(isRunning ? "Running..." : "Run")
                    .frame(minWidth: 200)
                    .padding()
                    .background(isRunning ? Color.gray : Color.blue)
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

}

#Preview {
    ContentView()
}
