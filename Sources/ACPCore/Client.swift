//
//  Client.swift
//  ACP
//
//  Transport-backed ACP JSON-RPC client.
//

import ACPModel
import Foundation
import os

// MARK: - Debug Message Types

public enum DebugMessageDirection: Sendable {
    case outgoing
    case incoming
}

public struct DebugMessage: Sendable {
    public let direction: DebugMessageDirection
    public let timestamp: Date
    public let rawData: Data
    public let method: String?

    public var jsonString: String? {
        String(data: rawData, encoding: .utf8)
    }
}

public actor Client {
    private struct PendingRequest {
        let continuation: CheckedContinuation<JSONRPCResponse, any Error>
        var timeoutTask: Task<Void, Never>?
    }

    let decoder = JSONDecoder()
    let encoder: JSONEncoder
    let requestRouter: ACPRequestRouter

    private let logger = Logger.forCategory("Client")
    private let notificationStream: AsyncThrowingStream<JSONRPCNotification, any Error>
    private let notificationContinuation: AsyncThrowingStream<JSONRPCNotification, any Error>.Continuation

    private var transport: (any Transport)?
    private var messageTask: Task<Void, Never>?
    private var pendingRequests: [RequestId: PendingRequest] = [:]
    private var nextRequestID = 1
    private var isTerminating = false

    private var debugContinuation: AsyncStream<DebugMessage>.Continuation?
    private var debugStream: AsyncStream<DebugMessage>?

    public weak var delegate: (any ClientDelegate)?

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        self.encoder = encoder
        requestRouter = ACPRequestRouter(encoder: encoder, decoder: decoder)
        (notificationStream, notificationContinuation) = AsyncThrowingStream.makeStream()
    }

    public init(transport: any Transport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        self.encoder = encoder
        self.transport = transport
        requestRouter = ACPRequestRouter(encoder: encoder, decoder: decoder)
        (notificationStream, notificationContinuation) = AsyncThrowingStream.makeStream()
    }

    /// Notifications received from the agent.
    ///
    /// The stream throws if the underlying transport fails.
    nonisolated public var notifications: AsyncThrowingStream<JSONRPCNotification, any Error> {
        notificationStream
    }

    public var debugMessages: AsyncStream<DebugMessage>? {
        debugStream
    }

    public func enableDebugStream() {
        guard debugStream == nil else { return }
        (debugStream, debugContinuation) = AsyncStream.makeStream()
    }

    public func disableDebugStream() {
        debugContinuation?.finish()
        debugContinuation = nil
        debugStream = nil
    }

    /// Opens the configured transport and starts processing incoming messages.
    public func connect() async throws {
        guard messageTask == nil else { return }
        guard let transport else {
            throw ClientError.transportError("No transport is configured")
        }

        isTerminating = false
        if !(await transport.isConnected) {
            try await transport.connect()
        }
        startMessageLoop(for: transport)
    }

    /// Installs and opens a transport on a client created without one.
    public func connect(transport newTransport: any Transport) async throws {
        guard transport == nil else {
            throw ClientError.transportError("A transport is already configured")
        }

        transport = newTransport
        do {
            try await connect()
        } catch {
            transport = nil
            throw error
        }
    }

    /// Returns the configured transport when it has the requested concrete type.
    public func configuredTransport<TransportValue: Transport>(
        as _: TransportValue.Type
    ) -> TransportValue? {
        transport as? TransportValue
    }

    public func setDelegate(_ delegate: (any ClientDelegate)?) async {
        self.delegate = delegate
        await requestRouter.setDelegate(delegate)
    }

    public func setPermissionDelegate(_ delegate: (any ClientPermissionDelegate)?) async {
        await requestRouter.setPermissionDelegate(delegate)
    }

    /// Calls an arbitrary JSON-RPC method without parameters.
    ///
    /// Use this for protocol extensions that are not represented by the package's typed ACP APIs.
    /// ACP extension method names begin with an underscore; the client keeps the name opaque.
    public func sendRequest(
        method: String,
        timeout: Duration? = nil
    ) async throws -> JSONRPCResponse {
        try await sendRequest(method: method, encodedParams: nil, timeout: timeout)
    }

    /// Calls an arbitrary JSON-RPC method with an encodable parameter payload.
    ///
    /// Custom payloads may include `_meta`; the client transmits the method and payload without
    /// interpreting vendor-specific semantics.
    public func sendRequest<Parameters: Encodable & Sendable>(
        method: String,
        params: Parameters,
        timeout: Duration? = nil
    ) async throws -> JSONRPCResponse {
        try await sendRequest(
            method: method,
            encodedParams: try encodeAnyCodable(params),
            timeout: timeout
        )
    }

    /// Calls an arbitrary JSON-RPC method and decodes its result.
    public func sendRequest<Response: Decodable & Sendable>(
        method: String,
        as responseType: Response.Type,
        timeout: Duration? = nil
    ) async throws -> Response {
        let response = try await sendRequest(method: method, timeout: timeout)
        return try decodeResponse(response, as: responseType)
    }

    /// Calls an arbitrary JSON-RPC method and decodes its result.
    ///
    /// `_meta` remains available when it is represented by the caller's response type.
    public func sendRequest<Parameters, Response>(
        method: String,
        params: Parameters,
        as responseType: Response.Type,
        timeout: Duration? = nil
    ) async throws -> Response
    where Parameters: Encodable & Sendable, Response: Decodable & Sendable {
        let response = try await sendRequest(method: method, params: params, timeout: timeout)
        return try decodeResponse(response, as: responseType)
    }

    /// Sends an arbitrary JSON-RPC notification without parameters.
    public func sendNotification(method: String) async throws {
        try await sendNotification(method: method, encodedParams: nil)
    }

    /// Sends an arbitrary JSON-RPC notification with an encodable parameter payload.
    public func sendNotification<Parameters: Encodable & Sendable>(
        method: String,
        params: Parameters
    ) async throws {
        try await sendNotification(method: method, encodedParams: try encodeAnyCodable(params))
    }

    public func sendCancelNotification(sessionId: SessionId) async throws {
        try await sendNotification(
            method: "session/cancel",
            params: CancelSessionRequest(sessionId: sessionId)
        )
    }

    public func sendCancelRequest(requestId: RequestId) async throws {
        try await sendNotification(
            method: "$/cancel_request",
            params: CancelRequestNotification(requestId: requestId)
        )
    }

    public func terminate() async {
        isTerminating = true
        failPendingRequests(with: ClientError.processNotRunning)

        let messageTask = messageTask
        self.messageTask = nil
        messageTask?.cancel()
        await transport?.close()
        await messageTask?.value
        transport = nil

        notificationContinuation.finish()
        debugContinuation?.finish()
        debugContinuation = nil
        debugStream = nil
    }
}

extension Client {
    func encodeAnyCodable<Value: Encodable>(_ value: Value) throws -> AnyCodable {
        try decoder.decode(AnyCodable.self, from: encoder.encode(value))
    }

    func decodeResponse<Response: Decodable>(
        _ response: JSONRPCResponse,
        as responseType: Response.Type
    ) throws -> Response {
        if let error = response.error {
            throw ClientError.agentError(error)
        }
        guard let result = response.result else {
            throw ClientError.invalidResponse
        }
        return try decoder.decode(responseType, from: encoder.encode(result))
    }

    func decodeEmptyTolerantResponse<Response: Decodable>(
        _ response: JSONRPCResponse,
        emptyValue: @autoclosure () -> Response
    ) throws -> Response {
        if let error = response.error {
            throw ClientError.agentError(error)
        }
        guard let result = response.result, !(result.value is NSNull) else {
            return emptyValue()
        }
        if let dictionary = result.value as? [String: any Sendable], dictionary.isEmpty {
            return emptyValue()
        }
        return try decoder.decode(Response.self, from: encoder.encode(result))
    }

    private func sendRequest(
        method: String,
        encodedParams: AnyCodable?,
        timeout: Duration?
    ) async throws -> JSONRPCResponse {
        try Task.checkCancellation()
        guard await transport?.isConnected == true else {
            throw ClientError.processNotRunning
        }

        let requestID = RequestId.number(nextRequestID)
        nextRequestID += 1
        let request = JSONRPCRequest(id: requestID, method: method, params: encodedParams)
        return try await send(request, method: method, timeout: timeout)
    }

    private func sendNotification(
        method: String,
        encodedParams: AnyCodable?
    ) async throws {
        guard await transport?.isConnected == true else {
            throw ClientError.processNotRunning
        }
        let notification = JSONRPCNotification(method: method, params: encodedParams)
        try await writeMessageWithDebug(notification, method: method)
    }

    private func send(
        _ request: JSONRPCRequest,
        method: String,
        timeout: Duration?
    ) async throws -> JSONRPCResponse {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = timeout.map { duration in
                    Task { [weak self] in
                        do {
                            try await Task.sleep(for: duration)
                            await self?.timeOutRequest(request.id)
                        } catch {
                            // The response arrived or the caller cancelled before the deadline.
                        }
                    }
                }
                pendingRequests[request.id] = PendingRequest(
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )

                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.writeMessageWithDebug(request, method: method)
                    } catch {
                        await self.failRequest(request.id, with: error)
                    }
                }
            }
        } onCancel: {
            Task { await self.cancelRequest(request.id) }
        }
    }

    private func timeOutRequest(_ requestID: RequestId) async {
        guard let pending = pendingRequests.removeValue(forKey: requestID) else { return }
        pending.continuation.resume(throwing: ClientError.requestTimeout)
        try? await sendCancelRequest(requestId: requestID)
    }

    private func cancelRequest(_ requestID: RequestId) async {
        guard let pending = pendingRequests.removeValue(forKey: requestID) else { return }
        pending.timeoutTask?.cancel()
        pending.continuation.resume(throwing: CancellationError())
        try? await sendCancelRequest(requestId: requestID)
    }

    private func failRequest(_ requestID: RequestId, with error: any Error) {
        guard let pending = pendingRequests.removeValue(forKey: requestID) else { return }
        pending.timeoutTask?.cancel()
        pending.continuation.resume(throwing: error)
    }

    private func failPendingRequests(with error: any Error) {
        let requests = pendingRequests.values
        pendingRequests.removeAll()
        for request in requests {
            request.timeoutTask?.cancel()
            request.continuation.resume(throwing: error)
        }
    }
}

extension Client {
    private func startMessageLoop(for transport: any Transport) {
        messageTask = Task { [weak self, transport] in
            do {
                for try await data in transport.messages {
                    guard !Task.isCancelled else { return }
                    await self?.handleMessage(data)
                }
                await self?.transportDidClose(throwing: nil)
            } catch {
                await self?.transportDidClose(throwing: error)
            }
        }
    }

    private func handleMessage(_ data: Data) async {
        guard !data.isEmpty else { return }
        emitDebugMessage(direction: .incoming, data: data, method: extractMethod(from: data))

        do {
            switch try decoder.decode(Message.self, from: data) {
            case .response(let response):
                handleResponse(response)
            case .notification(let notification):
                notificationContinuation.yield(notification)
                try await requestRouter.routeNotification(notification)
            case .request(let request):
                Task { [weak self] in
                    await self?.handleIncomingRequest(request)
                }
            }
        } catch {
            logger.warning("Failed to process ACP message: \(error.localizedDescription)")
        }
    }

    private func handleResponse(_ response: JSONRPCResponse) {
        guard let pending = pendingRequests.removeValue(forKey: response.id) else {
            logger.warning("Received a response for unknown request \(response.id.description)")
            return
        }
        pending.timeoutTask?.cancel()
        pending.continuation.resume(returning: response)
    }

    private func handleIncomingRequest(_ request: JSONRPCRequest) async {
        do {
            let result = try await requestRouter.routeRequest(request)
            let response = JSONRPCResponse(id: request.id, result: result, error: nil)
            try await writeMessageWithDebug(response)
        } catch {
            let code = error is ClientError ? -32601 : -32603
            let response = JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(code: code, message: error.localizedDescription, data: nil)
            )
            try? await writeMessageWithDebug(response)
        }
    }

    private func transportDidClose(throwing error: (any Error)?) {
        guard !isTerminating else { return }
        let failure = mappedTransportError(error)
        failPendingRequests(with: failure)
        notificationContinuation.finish(throwing: failure)
        messageTask = nil
    }

    private func mappedTransportError(_ error: (any Error)?) -> any Error {
        if let transportError = error as? any ClientTransportError {
            return transportError.clientError
        }
        return error ?? ClientError.connectionClosed
    }

    private func writeMessageWithDebug<MessageValue: Encodable>(
        _ message: MessageValue,
        method: String? = nil
    ) async throws {
        guard let transport else {
            throw ClientError.processNotRunning
        }
        let data = try encoder.encode(message)
        emitDebugMessage(direction: .outgoing, data: data, method: method)
        try await transport.send(data)
    }

    private func emitDebugMessage(
        direction: DebugMessageDirection,
        data: Data,
        method: String?
    ) {
        debugContinuation?.yield(
            DebugMessage(
                direction: direction,
                timestamp: .now,
                rawData: data,
                method: method
            )
        )
    }

    private func extractMethod(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["method"] as? String
    }
}

@available(*, deprecated, renamed: "Client")
public typealias ACPClient = Client
