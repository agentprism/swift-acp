//
//  ClientDelegate.swift
//  ACP
//
//  Main delegate protocol for ACP client
//

import ACPModel
import Foundation

/// Handles permission requests initiated by an ACP agent.
public protocol ClientPermissionDelegate: AnyObject, Sendable {
    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse
}

/// Protocol for handling incoming ACP requests from the agent
public protocol ClientDelegate: ClientPermissionDelegate {
    /// Handle file read request
    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws
        -> ReadTextFileResponse

    /// Handle file write request
    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws
        -> WriteTextFileResponse

    /// Handle terminal create request
    func handleTerminalCreate(
        command: String, sessionId: String, args: [String]?, cwd: String?, env: [EnvVariable]?, outputByteLimit: Int?
    ) async throws -> CreateTerminalResponse

    /// Handle terminal output request
    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse

    /// Handle terminal wait for exit request
    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse

    /// Handle terminal kill request
    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse

    /// Handle terminal release request
    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse

    /// Handle permission request
    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse

    /// Handle MCP-over-ACP connect request
    func handleMcpConnect(_ request: ConnectMcpRequest) async throws -> ConnectMcpResponse

    /// Handle MCP-over-ACP request message
    func handleMcpMessage(_ request: MessageMcpRequest) async throws -> MessageMcpResponse

    /// Handle MCP-over-ACP disconnect request
    func handleMcpDisconnect(_ request: DisconnectMcpRequest) async throws -> DisconnectMcpResponse

    /// Handle MCP-over-ACP notification message
    func handleMcpNotification(_ notification: MessageMcpNotification) async throws

    /// Handle structured user input elicitation request
    func handleCreateElicitation(_ request: CreateElicitationRequest) async throws -> CreateElicitationResponse

    /// Handle URL-based elicitation completion notification
    func handleCompleteElicitation(_ notification: CompleteElicitationNotification) async throws
}

extension ClientDelegate {
    public func handleMcpConnect(_: ConnectMcpRequest) throws -> ConnectMcpResponse {
        throw ClientError.invalidResponse
    }

    public func handleMcpMessage(_: MessageMcpRequest) throws -> MessageMcpResponse {
        throw ClientError.invalidResponse
    }

    public func handleMcpDisconnect(_: DisconnectMcpRequest) throws -> DisconnectMcpResponse {
        throw ClientError.invalidResponse
    }

    public func handleMcpNotification(_: MessageMcpNotification) {
        // Default: no-op
    }

    public func handleCreateElicitation(_: CreateElicitationRequest) throws -> CreateElicitationResponse {
        throw ClientError.invalidResponse
    }

    public func handleCompleteElicitation(_: CompleteElicitationNotification) {
        // Default: no-op
    }
}

// MARK: - Typealiases for backward compatibility

@available(*, deprecated, renamed: "ClientDelegate")
public typealias ACPClientDelegate = ClientDelegate
