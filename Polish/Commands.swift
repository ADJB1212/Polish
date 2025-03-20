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
            command: "PATH=$PATH:/usr/local/bin:/opt/homebrew/bin brew cleanup",
            completion: completion)
        runCommand(
            command: "PATH=$PATH:/usr/local/bin:/opt/homebrew/bin brew autoremove",
            completion: completion)
    }

    static func runPipCommandForAllPythons(
        pipCommand: String, completion: @escaping (String) -> Void
    ) {
        // Use a single command to find Python installations and run pip command for each
        let command = """
            # Collect Python paths
            PYTHON_PATHS=$(
            {
                # Standard path executables
                which -a python python2 python3 python3.9 python3.10 python3.11 python3.12 2>/dev/null

                # Homebrew installations
                for brewpath in /usr/local/bin /opt/homebrew/bin; do
                    if [ -d "$brewpath" ]; then
                        ls -1 $brewpath/python* 2>/dev/null | grep -v config
                    fi
                done

                # Check pyenv if installed
                if command -v pyenv >/dev/null; then
                    pyenv which python 2>/dev/null
                    for ver in $(pyenv versions --bare 2>/dev/null); do
                        echo "$HOME/.pyenv/versions/$ver/bin/python"
                    done
                fi

                # Check conda environments if conda exists
                if command -v conda >/dev/null; then
                    conda info --envs 2>/dev/null | grep -v "#" | awk '{print $NF"/bin/python"}' | grep -v "^/"
                fi
            } | sort | uniq | xargs -I{} sh -c 'if [ -x "{}" ] && [ -f "{}" ]; then echo "{}"; fi'
            )

            # If no Python installations found, try with default python3
            if [ -z "$PYTHON_PATHS" ]; then
                if command -v python3 >/dev/null; then
                    python3 -m pip \(pipCommand)
                fi
                exit 0
            fi

            # Process each Python installation
            echo "$PYTHON_PATHS" | while read python_exe; do
                # Skip empty lines
                [ -z "$python_exe" ] && continue

                $python_exe --version
                $python_exe -m pip \(pipCommand)
            done
            """

        runCommand(command: command, completion: completion)
    }

    private static func runCommand(command: String, completion: @escaping (String) -> Void) {
        var outputText = ""
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
