//
//  Client+Extensions.swift
//  ACP
//
//  Draft and extension ACP client operations.
//

import ACPModel

extension Client {
    public func listProviders() async throws -> ListProvidersResponse {
        try await sendRequest(
            method: "providers/list",
            params: ListProvidersRequest(),
            as: ListProvidersResponse.self
        )
    }

    public func setProvider(
        providerId: ProviderId,
        apiType: LlmProtocol,
        baseUrl: String,
        headers: [String: String]? = nil
    ) async throws -> SetProviderResponse {
        let response = try await sendRequest(
            method: "providers/set",
            params: SetProviderRequest(
                providerId: providerId,
                apiType: apiType,
                baseUrl: baseUrl,
                headers: headers
            )
        )
        return try decodeEmptyTolerantResponse(response, emptyValue: SetProviderResponse())
    }

    public func disableProvider(providerId: ProviderId) async throws -> DisableProviderResponse {
        let response = try await sendRequest(
            method: "providers/disable",
            params: DisableProviderRequest(providerId: providerId)
        )
        return try decodeEmptyTolerantResponse(response, emptyValue: DisableProviderResponse())
    }
}

extension Client {
    public func startNes(
        workspaceUri: String? = nil,
        workspaceFolders: [WorkspaceFolder]? = nil,
        repository: NesRepository? = nil
    ) async throws -> StartNesResponse {
        try await sendRequest(
            method: "nes/start",
            params: StartNesRequest(
                workspaceUri: workspaceUri,
                workspaceFolders: workspaceFolders,
                repository: repository
            ),
            as: StartNesResponse.self
        )
    }

    public func suggestNes(
        sessionId: SessionId,
        uri: String,
        version: Int64,
        position: TextPosition,
        selection: ACPModel.TextRange? = nil,
        triggerKind: NesTriggerKind,
        context: NesSuggestContext? = nil
    ) async throws -> SuggestNesResponse {
        try await sendRequest(
            method: "nes/suggest",
            params: SuggestNesRequest(
                sessionId: sessionId,
                uri: uri,
                version: version,
                position: position,
                selection: selection,
                triggerKind: triggerKind,
                context: context
            ),
            as: SuggestNesResponse.self
        )
    }

    public func acceptNesSuggestion(sessionId: SessionId, id: String) async throws {
        try await sendNotification(
            method: "nes/accept",
            params: AcceptNesNotification(sessionId: sessionId, id: id)
        )
    }

    public func rejectNesSuggestion(
        sessionId: SessionId,
        id: String,
        reason: NesRejectReason? = nil
    ) async throws {
        try await sendNotification(
            method: "nes/reject",
            params: RejectNesNotification(sessionId: sessionId, id: id, reason: reason)
        )
    }

    public func closeNes(sessionId: SessionId) async throws -> CloseNesResponse {
        let response = try await sendRequest(
            method: "nes/close",
            params: CloseNesRequest(sessionId: sessionId)
        )
        return try decodeEmptyTolerantResponse(response, emptyValue: CloseNesResponse())
    }
}

extension Client {
    public func sendMcpMessage(
        connectionId: McpConnectionId,
        method: String,
        params: AnyCodable? = nil
    ) async throws -> MessageMcpResponse {
        try await sendRequest(
            method: "mcp/message",
            params: MessageMcpRequest(connectionId: connectionId, method: method, params: params),
            as: MessageMcpResponse.self
        )
    }

    public func sendMcpMessageNotification(
        connectionId: McpConnectionId,
        method: String,
        params: AnyCodable? = nil
    ) async throws {
        try await sendNotification(
            method: "mcp/message",
            params: MessageMcpNotification(connectionId: connectionId, method: method, params: params)
        )
    }
}

extension Client {
    public func didOpenDocument(
        sessionId: SessionId,
        uri: String,
        languageId: String,
        version: Int64,
        text: String
    ) async throws {
        try await sendNotification(
            method: "document/didOpen",
            params: DidOpenDocumentNotification(
                sessionId: sessionId,
                uri: uri,
                languageId: languageId,
                version: version,
                text: text
            )
        )
    }

    public func didChangeDocument(
        sessionId: SessionId,
        uri: String,
        version: Int64,
        contentChanges: [TextDocumentContentChangeEvent]
    ) async throws {
        try await sendNotification(
            method: "document/didChange",
            params: DidChangeDocumentNotification(
                sessionId: sessionId,
                uri: uri,
                version: version,
                contentChanges: contentChanges
            )
        )
    }

    public func didCloseDocument(sessionId: SessionId, uri: String) async throws {
        try await sendNotification(
            method: "document/didClose",
            params: DidCloseDocumentNotification(sessionId: sessionId, uri: uri)
        )
    }

    public func didSaveDocument(sessionId: SessionId, uri: String) async throws {
        try await sendNotification(
            method: "document/didSave",
            params: DidSaveDocumentNotification(sessionId: sessionId, uri: uri)
        )
    }

    public func didFocusDocument(
        sessionId: SessionId,
        uri: String,
        version: Int64,
        position: TextPosition,
        visibleRange: ACPModel.TextRange
    ) async throws {
        try await sendNotification(
            method: "document/didFocus",
            params: DidFocusDocumentNotification(
                sessionId: sessionId,
                uri: uri,
                version: version,
                position: position,
                visibleRange: visibleRange
            )
        )
    }
}
