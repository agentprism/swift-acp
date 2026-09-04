//
//  ShellEnvironment.swift
//  ACP
//
//  Login-shell environment loading backed by swift-subprocess.
//

#if os(macOS)
    import Foundation
    import Subprocess

    public enum ShellEnvironment: Sendable {
        /// Returns the user's login-shell environment, cached after the first load.
        public static func loadUserShellEnvironment() async -> [String: String] {
            await ShellEnvironmentCache.shared.values()
        }

        /// Compatibility spelling for the asynchronous environment loader.
        public static func loadUserShellEnvironmentAsync() async -> [String: String] {
            await loadUserShellEnvironment()
        }

        /// Starts loading the login-shell environment without blocking the caller.
        public static func preloadEnvironment() {
            Task {
                _ = await loadUserShellEnvironment()
            }
        }

        /// Clears and reloads the cached login-shell environment.
        public static func reloadEnvironment() async {
            await ShellEnvironmentCache.shared.reload()
        }
    }

    private actor ShellEnvironmentCache {
        static let shared = ShellEnvironmentCache()

        private var cachedEnvironment: [String: String]?

        func values() async -> [String: String] {
            if let cachedEnvironment {
                return cachedEnvironment
            }

            let environment = await loadEnvironmentFromShell()
            cachedEnvironment = environment
            return environment
        }

        func reload() async {
            cachedEnvironment = nil
            _ = await values()
        }

        private func loadEnvironmentFromShell() async -> [String: String] {
            let inheritedEnvironment = ProcessInfo.processInfo.environment
            let shell = inheritedEnvironment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
            let shellName = URL(fileURLWithPath: shell).lastPathComponent
            let arguments: [String]
            switch shellName {
            case "fish":
                arguments = ["-l", "-c", "env"]
            case "zsh", "bash":
                arguments = ["-l", "-i", "-c", "env"]
            case "sh":
                arguments = ["-l", "-c", "env"]
            default:
                arguments = ["-c", "env"]
            }

            do {
                let result = try await Subprocess.run(
                    .path(.init(shell)),
                    arguments: Arguments(arguments),
                    environment: .inherit,
                    workingDirectory: .init(FileManager.default.homeDirectoryForCurrentUser.path),
                    output: .string(limit: 1_024 * 1_024),
                    error: .discarded
                )
                guard result.terminationStatus.isSuccess else {
                    return inheritedEnvironment
                }

                var environment: [String: String] = [:]
                for line in result.standardOutput.split(separator: "\n") {
                    guard let separator = line.firstIndex(of: "=") else { continue }
                    environment[String(line[..<separator])] = String(line[line.index(after: separator)...])
                }
                return environment.isEmpty ? inheritedEnvironment : environment
            } catch {
                return inheritedEnvironment
            }
        }
    }
#endif
