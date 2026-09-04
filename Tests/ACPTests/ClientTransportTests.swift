//
//  ClientTransportTests.swift
//  ACPTests
//

import ACPModel
import Foundation
import XCTest

@testable import ACP

final class ClientTransportTests: XCTestCase {
    func testTransportBackedClientPreservesTypedRequestMetadata() async throws {
        let transport = LoopbackTransport { request in
            let response = InitializeResponse(
                protocolVersion: 1,
                agentCapabilities: AgentCapabilities(),
                agentInfo: AgentInfo(name: "test-agent", version: "1.0.0")
            )
            return JSONRPCResponse(
                id: request.id,
                result: try Self.anyCodable(response),
                error: nil
            )
        }
        let client = Client(transport: transport)
        try await client.connect()
        let request = InitializeRequest(
            protocolVersion: 1,
            clientCapabilities: ClientCapabilities(
                fs: FileSystemCapabilities(readTextFile: false, writeTextFile: false),
                terminal: false
            ),
            _meta: ["router": AnyCodable("backend")]
        )

        let response = try await client.initialize(request, timeout: .seconds(1))
        let sentData = await transport.nextSentMessage()
        let sentRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: sentData)
        let parameters = try XCTUnwrap(sentRequest.params)
        let decodedRequest = try JSONDecoder().decode(
            InitializeRequest.self,
            from: JSONEncoder().encode(parameters)
        )

        XCTAssertEqual(response.agentInfo?.name, "test-agent")
        XCTAssertEqual(decodedRequest._meta?["router"]?.value as? String, "backend")
        await client.terminate()
    }

    func testRequestTimeoutReturnsAndSendsCancellation() async throws {
        let transport = LoopbackTransport { _ in nil }
        let client = Client(transport: transport)
        try await client.connect()

        do {
            _ = try await client.sendRequest(
                method: "test/never-responds",
                params: ["value": "request"],
                timeout: .milliseconds(20)
            )
            XCTFail("Expected the request to time out")
        } catch ClientError.requestTimeout {
            // Expected.
        }

        _ = await transport.nextSentMessage()
        let cancellationData = await transport.nextSentMessage()
        let cancellation = try JSONDecoder().decode(JSONRPCNotification.self, from: cancellationData)
        XCTAssertEqual(cancellation.method, "$/cancel_request")
        await client.terminate()
    }

    func testTransportFailureFailsPendingRequestWithCause() async throws {
        let transport = LoopbackTransport { _ in nil }
        let client = Client(transport: transport)
        try await client.connect()

        let requestTask = Task {
            try await client.sendRequest(
                method: "test/disconnect",
                params: ["value": "request"]
            )
        }
        _ = await transport.nextSentMessage()
        await transport.fail(with: TestTransportError.disconnected)

        do {
            _ = try await requestTask.value
            XCTFail("Expected the transport failure")
        } catch TestTransportError.disconnected {
            // Expected.
        }
        await client.terminate()
    }

    private static func anyCodable<Value: Encodable>(_ value: Value) throws -> AnyCodable {
        try JSONDecoder().decode(AnyCodable.self, from: JSONEncoder().encode(value))
    }
}

private enum TestTransportError: Error {
    case disconnected
}

private actor LoopbackTransport: Transport {
    typealias Responder = @Sendable (JSONRPCRequest) throws -> JSONRPCResponse?

    nonisolated let messages: AsyncThrowingStream<Data, any Error>

    private let messageContinuation: AsyncThrowingStream<Data, any Error>.Continuation
    private let responder: Responder
    private var connected = false
    private var sentMessages: [Data] = []
    private var sentWaiters: [CheckedContinuation<Data, Never>] = []

    init(responder: @escaping Responder) {
        self.responder = responder
        (messages, messageContinuation) = AsyncThrowingStream.makeStream()
    }

    var isConnected: Bool {
        connected
    }

    func connect() async throws {
        await Task.yield()
        connected = true
    }

    func send(_ data: Data) async throws {
        await Task.yield()
        if let waiter = sentWaiters.first {
            sentWaiters.removeFirst()
            waiter.resume(returning: data)
        } else {
            sentMessages.append(data)
        }

        guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data),
            let response = try responder(request)
        else {
            return
        }
        messageContinuation.yield(try JSONEncoder().encode(response))
    }

    func close() async {
        await Task.yield()
        connected = false
        messageContinuation.finish()
    }

    func nextSentMessage() async -> Data {
        if !sentMessages.isEmpty {
            return sentMessages.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            sentWaiters.append(continuation)
        }
    }

    func fail(with error: any Error) {
        connected = false
        messageContinuation.finish(throwing: error)
    }
}
