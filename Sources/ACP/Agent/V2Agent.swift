//
//  V2Agent.swift
//  ACP
//
//  ACP v2 agent delegate surface.
//

import ACPModel

/// Handles ACP v2 client-to-agent operations.
///
/// Baseline session methods are required. Capability-gated methods have
/// default implementations that report them as unsupported.
public protocol V2AgentDelegate: AnyObject, Sendable {
    func handleInitialize(
        _ request: ACPV2.InitializeRequest
    ) async throws -> ACPV2.InitializeResponse

    func handleNewSession(
        _ request: ACPV2.NewSessionRequest
    ) async throws -> ACPV2.NewSessionResponse

    func handlePrompt(
        _ request: ACPV2.PromptRequest
    ) async throws -> ACPV2.PromptResponse

    func handleCancel(_ sessionId: ACPV2.SessionId) async throws

    func handleResumeSession(
        _ request: ACPV2.ResumeSessionRequest
    ) async throws -> ACPV2.ResumeSessionResponse

    func handleListSessions(
        _ request: ACPV2.ListSessionsRequest
    ) async throws -> ACPV2.ListSessionsResponse

    func handleCloseSession(
        _ request: ACPV2.CloseSessionRequest
    ) async throws -> ACPV2.CloseSessionResponse

    func handleDeleteSession(
        _ request: ACPV2.DeleteSessionRequest
    ) async throws -> ACPV2.DeleteSessionResponse

    func handleSetConfigOption(
        _ request: ACPV2.SetSessionConfigOptionRequest
    ) async throws -> ACPV2.SetSessionConfigOptionResponse

    func handleLogin(
        _ request: ACPV2.LoginAuthRequest
    ) async throws -> ACPV2.LoginAuthResponse

    func handleLogout(
        _ request: ACPV2.LogoutAuthRequest
    ) async throws -> ACPV2.LogoutAuthResponse

    /// Handles capability-gated or application extension requests.
    func handleV2Request(
        method: String,
        params: AnyCodable?
    ) async throws -> AnyCodable
}

public extension V2AgentDelegate {
    func handleCancel(_ sessionId: ACPV2.SessionId) async throws {}

    func handleResumeSession(
        _ request: ACPV2.ResumeSessionRequest
    ) async throws -> ACPV2.ResumeSessionResponse {
        throw ACPProtocolNegotiationError.unsupportedMethod("session/resume")
    }

    func handleListSessions(
        _ request: ACPV2.ListSessionsRequest
    ) async throws -> ACPV2.ListSessionsResponse {
        throw ACPProtocolNegotiationError.unsupportedMethod("session/list")
    }

    func handleCloseSession(
        _ request: ACPV2.CloseSessionRequest
    ) async throws -> ACPV2.CloseSessionResponse {
        throw ACPProtocolNegotiationError.unsupportedMethod("session/close")
    }

    func handleDeleteSession(
        _ request: ACPV2.DeleteSessionRequest
    ) async throws -> ACPV2.DeleteSessionResponse {
        throw ACPProtocolNegotiationError.unsupportedMethod("session/delete")
    }

    func handleSetConfigOption(
        _ request: ACPV2.SetSessionConfigOptionRequest
    ) async throws -> ACPV2.SetSessionConfigOptionResponse {
        throw ACPProtocolNegotiationError.unsupportedMethod("session/set_config_option")
    }

    func handleLogin(
        _ request: ACPV2.LoginAuthRequest
    ) async throws -> ACPV2.LoginAuthResponse {
        throw ACPProtocolNegotiationError.unsupportedMethod("auth/login")
    }

    func handleLogout(
        _ request: ACPV2.LogoutAuthRequest
    ) async throws -> ACPV2.LogoutAuthResponse {
        throw ACPProtocolNegotiationError.unsupportedMethod("auth/logout")
    }

    func handleV2Request(
        method: String,
        params: AnyCodable?
    ) async throws -> AnyCodable {
        throw ACPProtocolNegotiationError.unsupportedMethod(method)
    }
}
