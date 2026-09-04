//
//  Client+Sessions.swift
//  ACP
//
//  Typed ACP client operations.
//

import ACPModel
import Foundation

extension Client {
    /// Initializes a connection using the complete typed request, including `_meta`.
    public func initialize(
        _ request: InitializeRequest,
        timeout: Duration? = nil
    ) async throws -> InitializeResponse {
        try await sendRequest(
            method: "initialize",
            params: request,
            as: InitializeResponse.self,
            timeout: timeout
        )
    }

    public func initialize(
        protocolVersion: Int = 1,
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> InitializeResponse {
        let request = InitializeRequest(
            protocolVersion: protocolVersion,
            clientCapabilities: capabilities,
            clientInfo: clientInfo
                ?? ClientInfo(
                    name: "ACP",
                    title: "ACP Client",
                    version: "1.0.0"
                )
        )
        return try await initialize(request, timeout: duration(seconds: timeout))
    }

    /// Creates a session using the complete typed request, including `_meta`.
    public func newSession(
        _ request: NewSessionRequest,
        timeout: Duration? = nil
    ) async throws -> NewSessionResponse {
        try await sendRequest(
            method: "session/new",
            params: request,
            as: NewSessionResponse.self,
            timeout: timeout
        )
    }

    public func newSession(
        workingDirectory: String,
        additionalDirectories: [String]? = nil,
        mcpServers: [MCPServerConfig] = [],
        timeout: TimeInterval? = nil
    ) async throws -> NewSessionResponse {
        let request = NewSessionRequest(
            cwd: workingDirectory,
            additionalDirectories: additionalDirectories,
            mcpServers: mcpServers
        )
        return try await newSession(request, timeout: duration(seconds: timeout))
    }

    public func sendPrompt(
        sessionId: SessionId,
        content: [ContentBlock]
    ) async throws -> SessionPromptResponse {
        try await sendRequest(
            method: "session/prompt",
            params: SessionPromptRequest(sessionId: sessionId, prompt: content),
            as: SessionPromptResponse.self
        )
    }

    public func authenticate(
        authMethodId: String,
        credentials: [String: String]? = nil
    ) async throws -> AuthenticateResponse {
        let response = try await sendRequest(
            method: "authenticate",
            params: AuthenticateRequest(methodId: authMethodId, credentials: credentials)
        )
        do {
            return try decodeEmptyTolerantResponse(
                response,
                emptyValue: AuthenticateResponse(success: true, error: nil)
            )
        } catch is DecodingError {
            return AuthenticateResponse(success: true, error: nil)
        }
    }

    public func setMode(
        sessionId: SessionId,
        modeId: String
    ) async throws -> SetModeResponse {
        let response = try await sendRequest(
            method: "session/set_mode",
            params: SetModeRequest(sessionId: sessionId, modeId: modeId)
        )
        return try decodeEmptyTolerantResponse(response, emptyValue: SetModeResponse())
    }

    public func setModel(
        sessionId: SessionId,
        modelId: String
    ) async throws -> SetModelResponse {
        let response = try await sendRequest(
            method: "session/set_model",
            params: SetModelRequest(sessionId: sessionId, modelId: modelId)
        )
        return try decodeEmptyTolerantResponse(response, emptyValue: SetModelResponse())
    }

    public func setConfigOption(
        sessionId: SessionId,
        configId: SessionConfigId,
        value: SessionConfigValueId
    ) async throws -> SetSessionConfigOptionResponse {
        try await setConfigOption(
            sessionId: sessionId,
            configId: configId,
            value: .select(value)
        )
    }

    public func setConfigOption(
        sessionId: SessionId,
        configId: SessionConfigId,
        value: Bool
    ) async throws -> SetSessionConfigOptionResponse {
        try await setConfigOption(
            sessionId: sessionId,
            configId: configId,
            value: .boolean(value)
        )
    }

    public func setConfigOption(
        sessionId: SessionId,
        configId: SessionConfigId,
        value: SessionConfigOptionValue
    ) async throws -> SetSessionConfigOptionResponse {
        try await sendRequest(
            method: "session/set_config_option",
            params: SetSessionConfigOptionRequest(
                sessionId: sessionId,
                configId: configId,
                value: value
            ),
            as: SetSessionConfigOptionResponse.self
        )
    }

    public func cancelSession(sessionId: SessionId) async throws {
        try await sendCancelNotification(sessionId: sessionId)
    }

    public func loadSession(
        sessionId: SessionId,
        cwd: String,
        additionalDirectories: [String]? = nil,
        mcpServers: [MCPServerConfig] = []
    ) async throws -> LoadSessionResponse {
        let response = try await sendRequest(
            method: "session/load",
            params: LoadSessionRequest(
                sessionId: sessionId,
                cwd: cwd,
                additionalDirectories: additionalDirectories,
                mcpServers: mcpServers
            )
        )

        if let error = response.error {
            guard isSessionAlreadyActive(error) else {
                throw ClientError.agentError(error)
            }
            return LoadSessionResponse(sessionId: sessionId)
        }

        let extractedSessionID = extractSessionID(from: response.result)
        guard let result = response.result else {
            return LoadSessionResponse(sessionId: extractedSessionID)
        }

        let data = try encoder.encode(result)
        if let payload = try? decoder.decode(LoadSessionResponsePayload.self, from: data) {
            return LoadSessionResponse(
                sessionId: payload.sessionId ?? extractedSessionID,
                modes: payload.modes,
                models: payload.models,
                configOptions: payload.configOptions,
                _meta: payload._meta
            )
        }
        if let decoded = try? decoder.decode(LoadSessionResponse.self, from: data) {
            return decoded
        }
        return LoadSessionResponse(sessionId: extractedSessionID)
    }

    public func resumeSession(
        sessionId: SessionId,
        cwd: String,
        additionalDirectories: [String]? = nil,
        mcpServers: [MCPServerConfig] = []
    ) async throws -> ResumeSessionResponse {
        let response = try await sendRequest(
            method: "session/resume",
            params: ResumeSessionRequest(
                sessionId: sessionId,
                cwd: cwd,
                additionalDirectories: additionalDirectories,
                mcpServers: mcpServers
            )
        )
        return try decodeEmptyTolerantResponse(response, emptyValue: ResumeSessionResponse())
    }

    public func forkSession(
        sessionId: SessionId,
        cwd: String,
        additionalDirectories: [String]? = nil,
        mcpServers: [MCPServerConfig] = []
    ) async throws -> ForkSessionResponse {
        try await sendRequest(
            method: "session/fork",
            params: ForkSessionRequest(
                sessionId: sessionId,
                cwd: cwd,
                additionalDirectories: additionalDirectories,
                mcpServers: mcpServers
            ),
            as: ForkSessionResponse.self
        )
    }

    public func listSessions(
        cwd: String? = nil,
        cursor: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ListSessionsResponse {
        try await sendRequest(
            method: "session/list",
            params: ListSessionsRequest(cwd: cwd, cursor: cursor),
            as: ListSessionsResponse.self,
            timeout: duration(seconds: timeout)
        )
    }

    public func closeSession(sessionId: SessionId) async throws -> CloseSessionResponse {
        let response = try await sendRequest(
            method: "session/close",
            params: CloseSessionRequest(sessionId: sessionId)
        )
        return try decodeEmptyTolerantResponse(response, emptyValue: CloseSessionResponse())
    }

    public func deleteSession(sessionId: SessionId) async throws -> DeleteSessionResponse {
        let response = try await sendRequest(
            method: "session/delete",
            params: DeleteSessionRequest(sessionId: sessionId)
        )
        return try decodeEmptyTolerantResponse(response, emptyValue: DeleteSessionResponse())
    }

    public func logout() async throws -> LogoutResponse {
        let response = try await sendRequest(method: "logout", params: LogoutRequest())
        return try decodeEmptyTolerantResponse(response, emptyValue: LogoutResponse())
    }
}

extension Client {
    private struct LoadSessionResponsePayload: Decodable {
        let sessionId: SessionId?
        let modes: ModesInfo?
        let models: ModelsInfo?
        let configOptions: [SessionConfigOption]?
        let _meta: [String: AnyCodable]?
    }

    private func duration(seconds: TimeInterval?) -> Duration? {
        seconds.map(Duration.seconds)
    }

    private func extractSessionID(from result: AnyCodable?) -> SessionId? {
        guard let value = result?.value else { return nil }
        if let dictionary = value as? [String: any Sendable] {
            let camelCaseIdentifier = dictionary["sessionId"] as? String
            let snakeCaseIdentifier = dictionary["session_id"] as? String
            return (camelCaseIdentifier ?? snakeCaseIdentifier).map(SessionId.init)
        }
        if let dictionary = value as? [String: AnyCodable] {
            let camelCaseIdentifier = dictionary["sessionId"]?.value as? String
            let snakeCaseIdentifier = dictionary["session_id"]?.value as? String
            return (camelCaseIdentifier ?? snakeCaseIdentifier).map(SessionId.init)
        }
        return nil
    }

    private func isSessionAlreadyActive(_ error: JSONRPCError) -> Bool {
        let markers = ["already active", "already started", "already exists"]
        let errorMessage = error.message.lowercased()
        if markers.contains(where: errorMessage.contains) {
            return true
        }
        if let message = error.data?.value as? String {
            return markers.contains(where: message.lowercased().contains)
        }
        guard let data = error.data?.value as? [String: any Sendable] else {
            return false
        }
        guard let details = data["details"] as? String else {
            return false
        }
        return markers.contains(where: details.lowercased().contains)
    }
}
