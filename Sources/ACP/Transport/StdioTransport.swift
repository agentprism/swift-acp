//
//  StdioTransport.swift
//  ACP
//
//  STDIO transport backed by swift-subprocess.
//

#if os(macOS)
    import Foundation
    import Subprocess
    import os

    /// An executable resolved either through `PATH` or from an explicit filesystem path.
    public enum StdioExecutable: Equatable, Sendable {
        case name(String)
        case path(String)
    }

    /// Errors produced by ``StdioTransport``.
    public enum StdioTransportError: LocalizedError, Sendable {
        case alreadyConnected
        case executableNotConfigured
        case processExited(Int32)
        case processSignaled(Int32)
        case messageTooLarge(Int)

        public var errorDescription: String? {
            switch self {
            case .alreadyConnected:
                "The stdio transport is already connected."
            case .executableNotConfigured:
                "No executable was configured for the stdio transport."
            case .processExited(let code):
                "The ACP subprocess exited with code \(code)."
            case .processSignaled(let signal):
                "The ACP subprocess exited after signal \(signal)."
            case .messageTooLarge(let size):
                "The ACP subprocess emitted a message larger than the configured limit (\(size) bytes)."
            }
        }
    }

    /// A subprocess transport that exchanges newline-delimited ACP JSON-RPC messages over stdio.
    public actor StdioTransport: Transport {
        private enum Command: Sendable {
            case write(Data)
            case terminate
        }

        private struct LaunchConfiguration: Sendable {
            let executable: StdioExecutable
            let arguments: [String]
            let workingDirectory: String?
            let environment: [String: String]
        }

        private let configuration: TransportConfiguration
        private let environmentProvider: @Sendable () async -> [String: String]
        private let logger = Logger.forCategory("StdioTransport")
        private let messageStream: AsyncThrowingStream<Data, any Error>
        private let messageContinuation: AsyncThrowingStream<Data, any Error>.Continuation
        private let standardErrorStream: AsyncStream<String>
        private let standardErrorContinuation: AsyncStream<String>.Continuation

        private var launchConfiguration: LaunchConfiguration?
        private var processTask: Task<Void, Never>?
        private var commandContinuation: AsyncStream<Command>.Continuation?
        private var connectContinuation: CheckedContinuation<Void, any Error>?
        private var readBuffer = Data()
        private var connected = false
        private var closing = false
        private var processID: Int32?
        private var processGroupID: Int32?

        nonisolated public var messages: AsyncThrowingStream<Data, any Error> {
            messageStream
        }

        public var isConnected: Bool {
            connected
        }

        /// Complete stderr lines emitted by the subprocess.
        nonisolated public var stderrLines: AsyncStream<String> {
            standardErrorStream
        }

        public init(
            configuration: TransportConfiguration = .default,
            environmentProvider: @escaping @Sendable () async -> [String: String] = {
                await ShellEnvironment.loadUserShellEnvironment()
            }
        ) {
            self.configuration = configuration
            self.environmentProvider = environmentProvider
            (messageStream, messageContinuation) = AsyncThrowingStream.makeStream()
            (standardErrorStream, standardErrorContinuation) = AsyncStream.makeStream()
        }

        public init(
            executable: StdioExecutable,
            arguments: [String] = [],
            workingDirectory: String? = nil,
            environment: [String: String] = [:],
            configuration: TransportConfiguration = .default,
            environmentProvider: @escaping @Sendable () async -> [String: String] = {
                await ShellEnvironment.loadUserShellEnvironment()
            }
        ) {
            self.configuration = configuration
            self.environmentProvider = environmentProvider
            launchConfiguration = LaunchConfiguration(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
            (messageStream, messageContinuation) = AsyncThrowingStream.makeStream()
            (standardErrorStream, standardErrorContinuation) = AsyncStream.makeStream()
        }

        public func launch(
            executablePath: String,
            arguments: [String] = [],
            workingDirectory: String? = nil,
            environment: [String: String]? = nil
        ) async throws {
            let executable: StdioExecutable =
                executablePath.contains("/") ? .path(executablePath) : .name(executablePath)
            try await launch(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment ?? [:]
            )
        }

        public func launch(
            executable: StdioExecutable,
            arguments: [String] = [],
            workingDirectory: String? = nil,
            environment: [String: String] = [:]
        ) async throws {
            guard processTask == nil, !connected else {
                throw StdioTransportError.alreadyConnected
            }
            launchConfiguration = LaunchConfiguration(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
            try await connect()
        }

        public func connect() async throws {
            try Task.checkCancellation()
            guard processTask == nil, !connected else {
                throw StdioTransportError.alreadyConnected
            }
            guard let launchConfiguration else {
                throw StdioTransportError.executableNotConfigured
            }

            closing = false
            let (commands, continuation) = AsyncStream.makeStream(of: Command.self)
            commandContinuation = continuation

            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    connectContinuation = continuation
                    processTask = Task { [weak self] in
                        guard let self else { return }
                        await self.runProcess(configuration: launchConfiguration, commands: commands)
                    }
                }
                try Task.checkCancellation()
            } onCancel: {
                Task { await self.close() }
            }
        }

        public func send(_ data: Data) throws {
            guard connected, let commandContinuation else {
                throw ClientError.processNotRunning
            }

            var line = data
            line.append(0x0A)
            guard case .enqueued = commandContinuation.yield(.write(line)) else {
                throw ClientError.connectionClosed
            }
        }

        public func close() async {
            guard let processTask else {
                finishStreams(throwing: nil)
                return
            }

            closing = true
            connected = false
            commandContinuation?.yield(.terminate)
            commandContinuation?.finish()
            processTask.cancel()
            await processTask.value
            await removeRegisteredProcess()
            self.processTask = nil
            commandContinuation = nil
            processID = nil
            processGroupID = nil
            finishStreams(throwing: nil)
        }

        public func processIdentifier() -> Int32? {
            connected ? processID : nil
        }

        public func processGroupIdentifier() -> Int32? {
            connected ? processGroupID : nil
        }
    }

    extension StdioTransport {
        private func runProcess(
            configuration: LaunchConfiguration,
            commands: AsyncStream<Command>
        ) async {
            do {
                let environment = await processEnvironment(for: configuration)
                let platformOptions = makePlatformOptions()
                let result = try await Subprocess.run(
                    configuration.executable.subprocessExecutable,
                    arguments: Arguments(configuration.arguments),
                    environment: .custom(environment.subprocessEnvironment),
                    workingDirectory: configuration.workingDirectory.map { .init($0) },
                    platformOptions: platformOptions,
                    input: .inputWriter,
                    output: .sequence,
                    error: .sequence
                ) { execution in
                    await processDidLaunch(
                        identifier: execution.processIdentifier.value,
                        executable: configuration.executable.registryPath
                    )

                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await command in commands {
                                switch command {
                                case .write(let data):
                                    _ = try await execution.standardInputWriter.write(Array(data))
                                case .terminate:
                                    try await execution.standardInputWriter.finish()
                                    await execution.teardown(using: platformOptions.teardownSequence)
                                    return
                                }
                            }
                            try await execution.standardInputWriter.finish()
                        }
                        group.addTask {
                            for try await buffer in execution.standardOutput {
                                let data = buffer.withUnsafeBytes { Data($0) }
                                try await self.receiveStandardOutput(data)
                            }
                            await self.outputDidClose()
                        }
                        group.addTask {
                            for try await line in execution.standardError.strings(
                                bufferingPolicy: .maxLineLength(1_024 * 1_024)
                            ) where !line.isEmpty {
                                self.standardErrorContinuation.yield(line)
                            }
                        }
                        try await group.waitForAll()
                    }
                }
                await processDidExit(status: result.terminationStatus)
            } catch {
                await processDidFail(error)
            }
        }

        private func processEnvironment(for configuration: LaunchConfiguration) async -> [String: String] {
            var environment = await environmentProvider()
            for (key, value) in configuration.environment {
                environment[key] = value
            }

            if let workingDirectory = configuration.workingDirectory, !workingDirectory.isEmpty {
                environment["PWD"] = workingDirectory
                environment["OLDPWD"] = workingDirectory
            }

            if case .path(let path) = configuration.executable {
                let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
                if !directory.isEmpty {
                    environment["PATH"] = [directory, environment["PATH"]]
                        .compactMap { $0 }
                        .joined(separator: ":")
                }
            }
            return environment
        }

        private func makePlatformOptions() -> PlatformOptions {
            var options = PlatformOptions()
            options.createSession = true
            options.teardownSequence.append(
                .gracefulShutDown(
                    toProcessGroup: true,
                    allowedDurationToNextStep: .seconds(2)
                )
            )
            return options
        }

        private func processDidLaunch(identifier: Int32, executable: String) async {
            connected = true
            processID = identifier
            processGroupID = identifier
            await ProcessRegistry.shared.recordProcess(
                pid: identifier,
                pgid: identifier,
                agentPath: executable
            )
            connectContinuation?.resume()
            connectContinuation = nil
        }

        private func processDidExit(status: TerminationStatus) async {
            await removeRegisteredProcess()
            processTask = nil
            commandContinuation = nil
            connected = false

            guard !closing else {
                finishStreams(throwing: nil)
                return
            }

            switch status {
            case .exited(0):
                finishStreams(throwing: nil)
            case .exited(let code):
                finishStreams(throwing: StdioTransportError.processExited(code))
            case .signaled(let signal):
                finishStreams(throwing: StdioTransportError.processSignaled(signal))
            }
        }

        private func processDidFail(_ error: any Error) async {
            await removeRegisteredProcess()
            if let connectContinuation {
                self.connectContinuation = nil
                connectContinuation.resume(throwing: error)
            }
            processTask = nil
            commandContinuation = nil
            connected = false
            finishStreams(throwing: closing ? nil : error)
        }

        private func removeRegisteredProcess() async {
            await ProcessRegistry.shared.removeProcess(pid: processID, pgid: processGroupID)
        }

        private func outputDidClose() {
            commandContinuation?.finish()
        }

        private func finishStreams(throwing error: (any Error)?) {
            if let error {
                messageContinuation.finish(throwing: error)
            } else {
                messageContinuation.finish()
            }
            standardErrorContinuation.finish()
        }
    }

    extension StdioTransport {
        private func receiveStandardOutput(_ data: Data) throws {
            readBuffer.append(data)
            while let message = popNextMessage() {
                if configuration.maxMessageSize > 0, message.count > configuration.maxMessageSize {
                    throw StdioTransportError.messageTooLarge(message.count)
                }
                messageContinuation.yield(message)
            }
            if configuration.maxMessageSize > 0, readBuffer.count > configuration.maxMessageSize {
                throw StdioTransportError.messageTooLarge(readBuffer.count)
            }
        }

        private func popNextMessage() -> Data? {
            let whitespace: Set<UInt8> = [0x20, 0x09, 0x0D, 0x0A]

            while true {
                while let first = readBuffer.first, whitespace.contains(first) {
                    readBuffer.removeFirst()
                }
                guard let first = readBuffer.first else { return nil }
                guard first == 0x7B || first == 0x5B else {
                    guard discardLeadingNoise() else { return nil }
                    continue
                }

                let bytes = Array(readBuffer)
                if let endIndex = completeMessageEnd(in: bytes) {
                    let candidate = Data(bytes[0...endIndex])
                    guard isValidJSONMessage(candidate) else {
                        readBuffer.removeFirst()
                        continue
                    }
                    readBuffer.removeFirst(endIndex + 1)
                    return candidate
                }

                guard discardMalformedLine() else { return nil }
            }
        }

        private func discardLeadingNoise() -> Bool {
            if let jsonStart = readBuffer.firstIndex(where: { $0 == 0x7B || $0 == 0x5B }) {
                let count = readBuffer.distance(from: readBuffer.startIndex, to: jsonStart)
                readBuffer.removeFirst(count)
                logger.debug("Discarded \(count) non-JSON stdout bytes")
                return true
            }
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let count = readBuffer.distance(from: readBuffer.startIndex, to: newline) + 1
                readBuffer.removeFirst(count)
                return true
            }
            if readBuffer.count > configuration.bufferSize {
                readBuffer.removeAll(keepingCapacity: true)
            }
            return false
        }

        private func discardMalformedLine() -> Bool {
            guard let newline = readBuffer.firstIndex(of: 0x0A) else { return false }
            let line = Data(readBuffer.prefix(upTo: newline))
            guard !line.isEmpty, !isValidJSONMessage(line) else { return false }
            let count = readBuffer.distance(from: readBuffer.startIndex, to: newline) + 1
            readBuffer.removeFirst(count)
            logger.warning("Discarded a malformed JSON stdout line")
            return true
        }

        private func completeMessageEnd(in bytes: [UInt8]) -> Int? {
            var depth = 0
            var isInsideString = false
            var isEscaped = false

            for endIndex in bytes.indices {
                let byte = bytes[endIndex]
                if isInsideString {
                    if isEscaped {
                        isEscaped = false
                    } else if byte == 0x5C {
                        isEscaped = true
                    } else if byte == 0x22 {
                        isInsideString = false
                    }
                    continue
                }

                if byte == 0x22 {
                    isInsideString = true
                } else if byte == 0x7B || byte == 0x5B {
                    depth += 1
                } else if byte == 0x7D || byte == 0x5D {
                    depth -= 1
                    if depth == 0 { return endIndex }
                }
            }
            return nil
        }

        private func isValidJSONMessage(_ data: Data) -> Bool {
            guard let object = try? JSONSerialization.jsonObject(with: data) else {
                return false
            }
            return object is [String: Any] || object is [Any]
        }
    }

    extension StdioExecutable {
        fileprivate var subprocessExecutable: Subprocess.Executable {
            switch self {
            case .name(let name):
                .name(name)
            case .path(let path):
                .path(.init(path))
            }
        }

        fileprivate var registryPath: String {
            switch self {
            case .name(let name): name
            case .path(let path): path
            }
        }
    }

    extension Dictionary where Key == String, Value == String {
        fileprivate var subprocessEnvironment: [Subprocess.Environment.Key: String] {
            reduce(into: [:]) { result, element in
                guard let key = Subprocess.Environment.Key(rawValue: element.key) else { return }
                result[key] = element.value
            }
        }
    }
#endif
