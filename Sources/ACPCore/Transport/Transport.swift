//
//  Transport.swift
//  ACP
//
//  Transport protocol abstraction for ACP communication.
//

import Foundation

/// A bidirectional byte transport for ACP JSON-RPC messages.
///
/// Each transport has a single lifecycle and a single consumer for ``messages``.
/// Create a new transport to reconnect after calling ``close()``.
public protocol Transport: Sendable {
    /// Opens the transport and starts receiving messages.
    func connect() async throws

    /// Sends one complete JSON-RPC message.
    func send(_ data: Data) async throws

    /// Incoming complete JSON-RPC messages.
    ///
    /// The stream finishes by throwing when the underlying connection fails, allowing
    /// clients to distinguish a clean close from a transport failure.
    var messages: AsyncThrowingStream<Data, any Error> { get }

    /// Closes the transport connection and finishes ``messages``.
    func close() async

    /// Whether the transport is currently connected.
    var isConnected: Bool { get async }
}

/// A transport failure that provides the error surfaced by ``Client``.
public protocol ClientTransportError: Error, Sendable {
    var clientError: any Error { get }
}

/// Events emitted by transports for lifecycle management.
public enum TransportEvent: Sendable {
    case connected
    case disconnected((any Error)?)
    case message(Data)
}

/// Configuration shared by byte-stream transports.
public struct TransportConfiguration: Sendable {
    /// Maximum message size in bytes (`0` means unlimited).
    public let maxMessageSize: Int

    /// Read buffer size.
    public let bufferSize: Int

    public init(maxMessageSize: Int = 0, bufferSize: Int = 65_536) {
        self.maxMessageSize = maxMessageSize
        self.bufferSize = bufferSize
    }

    public static let `default` = Self()
}
