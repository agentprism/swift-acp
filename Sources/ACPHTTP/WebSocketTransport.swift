//
//  WebSocketTransport.swift
//  ACPHTTP
//
//  WebSocket transport for ACP JSON-RPC messages.
//

import ACPCore
import ACPModel
import Foundation
import os

/// A single-connection ACP transport backed by `URLSessionWebSocketTask`.
public actor WebSocketTransport: Transport {
    private let session: URLSession
    private let url: URL
    private let logger = Logger.forCategory("WebSocketTransport")
    private let messageStream: AsyncThrowingStream<Data, any Error>
    private let messageContinuation: AsyncThrowingStream<Data, any Error>.Continuation

    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connected = false
    private var closing = false

    nonisolated public var messages: AsyncThrowingStream<Data, any Error> {
        messageStream
    }

    public var isConnected: Bool {
        connected
    }

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
        (messageStream, messageContinuation) = AsyncThrowingStream.makeStream()
    }

    public func connect() async throws {
        guard webSocket == nil else {
            throw ClientError.transportError("The WebSocket transport is already connected")
        }

        closing = false
        let webSocket = session.webSocketTask(with: url)
        self.webSocket = webSocket
        connected = true
        webSocket.resume()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveMessages(from: webSocket)
        }
    }

    public func send(_ data: Data) async throws {
        guard let webSocket, connected else {
            throw ClientError.transportError("The WebSocket transport is not connected")
        }

        if let text = String(data: data, encoding: .utf8) {
            try await webSocket.send(.string(text))
        } else {
            try await webSocket.send(.data(data))
        }
    }

    public func close() async {
        closing = true
        connected = false
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        messageContinuation.finish()
    }

    private func receiveMessages(from webSocket: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled, connected {
                let message = try await webSocket.receive()
                switch message {
                case .data(let data):
                    messageContinuation.yield(data)
                case .string(let text):
                    messageContinuation.yield(Data(text.utf8))
                @unknown default:
                    logger.warning("Ignoring an unknown WebSocket message type")
                }
            }
        } catch {
            connected = false
            self.webSocket = nil
            guard !closing, !Task.isCancelled else {
                messageContinuation.finish()
                return
            }
            logger.error("WebSocket receive failed: \(error.localizedDescription)")
            messageContinuation.finish(throwing: error)
        }
    }
}

/// A convenience wrapper around a transport-backed ``Client``.
public actor WebSocketClient {
    nonisolated public let client: Client

    public init(url: URL, session: URLSession = .shared) {
        client = Client(transport: WebSocketTransport(url: url, session: session))
    }

    /// Connects and initializes using the complete request, including `_meta`.
    public func connect(
        _ request: InitializeRequest,
        timeout: Duration? = .seconds(30)
    ) async throws -> InitializeResponse {
        try await client.connect()
        do {
            return try await client.initialize(request, timeout: timeout)
        } catch {
            await client.terminate()
            throw error
        }
    }

    public func connect(
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo? = nil,
        timeout: Duration? = .seconds(30)
    ) async throws -> InitializeResponse {
        try await connect(
            InitializeRequest(
                protocolVersion: 1,
                clientCapabilities: capabilities,
                clientInfo: clientInfo
                    ?? ClientInfo(
                        name: "ACP",
                        title: "ACP WebSocket Client",
                        version: "1.0.0"
                    )
            ),
            timeout: timeout
        )
    }

    public func setDelegate(_ delegate: (any ClientDelegate)?) async {
        await client.setDelegate(delegate)
    }

    public func close() async {
        await client.terminate()
    }
}
