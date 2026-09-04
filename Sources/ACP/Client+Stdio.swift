//
//  Client+Stdio.swift
//  ACP
//
//  Client conveniences for the optional macOS stdio transport.
//

#if os(macOS)
    import ACPCore
    import ACPModel
    import Foundation

    extension Client {
        /// Launches an ACP agent using ``StdioTransport``.
        public func launch(
            agentPath: String,
            arguments: [String] = [],
            workingDirectory: String? = nil,
            environment: [String: String]? = nil
        ) async throws {
            let executable: StdioExecutable = agentPath.contains("/") ? .path(agentPath) : .name(agentPath)
            try await launch(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment ?? [:]
            )
        }

        /// Launches an ACP agent using an explicit path or `PATH` lookup.
        public func launch(
            executable: StdioExecutable,
            arguments: [String] = [],
            workingDirectory: String? = nil,
            environment: [String: String] = [:]
        ) async throws {
            let stdioTransport = StdioTransport(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
            try await connect(transport: stdioTransport)
        }

        /// The subprocess identifier when this client owns a stdio transport.
        public func processIdentifier() async -> Int32? {
            guard let stdioTransport = configuredTransport(as: StdioTransport.self) else { return nil }
            return await stdioTransport.processIdentifier()
        }

        /// The subprocess group identifier when this client owns a stdio transport.
        public func processGroupIdentifier() async -> Int32? {
            guard let stdioTransport = configuredTransport(as: StdioTransport.self) else { return nil }
            return await stdioTransport.processGroupIdentifier()
        }

        /// Complete stderr lines from the owned stdio subprocess.
        public func stderrLines() -> AsyncStream<String>? {
            guard let stdioTransport = configuredTransport(as: StdioTransport.self) else { return nil }
            return stdioTransport.stderrLines
        }
    }

    extension StdioTransportError: ClientTransportError {
        public var clientError: any Error {
            switch self {
            case .processExited(let code):
                code == 0 ? ClientError.connectionClosed : ClientError.processFailed(code)
            case .processSignaled(let signal):
                ClientError.processFailed(-signal)
            default:
                self
            }
        }
    }
#endif
