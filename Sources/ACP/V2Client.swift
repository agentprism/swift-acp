//
//  V2Client.swift
//  ACP
//
//  Strict and negotiating ACP v2 client APIs.
//

import Foundation
import ACPModel

public enum ACPProtocolSelection: Sendable, Equatable {
    case v1
    case v2
    case automatic
}

public enum ACPProtocolNegotiationError: Error, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case notInitialized
    case alreadyInitialized
    case unsupportedMethod(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Unsupported ACP protocol version \(version)"
        case .notInitialized:
            return "The ACP connection has not been initialized"
        case .alreadyInitialized:
            return "The ACP connection has already been initialized"
        case .unsupportedMethod(let method):
            return "Unsupported ACP method: \(method)"
        }
    }
}

public protocol V2ClientDelegate: AnyObject, Sendable {
    func handlePermissionRequest(
        _ request: ACPV2.RequestPermissionRequest
    ) async throws -> ACPV2.RequestPermissionResponse

    func handleElicitationRequest(
        _ request: ACPV2.CreateElicitationRequest
    ) async throws -> ACPV2.CreateElicitationResponse

    func handleElicitationComplete(
        _ notification: ACPV2.CompleteElicitationNotification
    ) async throws

    /// Handles capability-gated or application extension requests.
    func handleV2Request(
        method: String,
        params: AnyCodable?
    ) async throws -> AnyCodable
}

public extension V2ClientDelegate {
    func handleElicitationRequest(
        _ request: ACPV2.CreateElicitationRequest
    ) async throws -> ACPV2.CreateElicitationResponse {
        throw ACPProtocolNegotiationError.unsupportedMethod("elicitation/create")
    }

    func handleElicitationComplete(
        _ notification: ACPV2.CompleteElicitationNotification
    ) async throws {}

    func handleV2Request(
        method: String,
        params: AnyCodable?
    ) async throws -> AnyCodable {
        throw ACPProtocolNegotiationError.unsupportedMethod(method)
    }
}

public enum ACPInitializeOutcome: Sendable {
    case v1(InitializeResponse)
    case v2(ACPV2.InitializeResponse)
}

/// A typed ACP v2 façade over the shared JSON-RPC subprocess client.
public actor V2Client {
    public nonisolated let base: Client

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let updateContinuation: AsyncStream<ACPV2.SessionUpdateNotification>.Continuation
    public nonisolated let updates: AsyncStream<ACPV2.SessionUpdateNotification>

    private weak var delegate: V2ClientDelegate?
    private var updateTask: Task<Void, Never>?
    private var initialized = false

    public init(base: Client = Client()) {
        self.base = base
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.withoutEscapingSlashes]
        self.decoder = JSONDecoder()

        var continuation: AsyncStream<ACPV2.SessionUpdateNotification>.Continuation!
        self.updates = AsyncStream { continuation = $0 }
        self.updateContinuation = continuation
    }

    public func setDelegate(_ delegate: V2ClientDelegate?) async {
        self.delegate = delegate
        guard let delegate else {
            await base.setRequestHandler(nil)
            return
        }

        await base.setRequestHandler { [weak delegate] request in
            guard let delegate else {
                throw ClientError.delegateNotSet
            }

            if request.method == "session/request_permission" {
                guard let params = request.params else {
                    throw ClientError.invalidResponse
                }
                let encoder = JSONEncoder()
                let decoder = JSONDecoder()
                let data = try encoder.encode(params)
                let decoded = try decoder.decode(
                    ACPV2.RequestPermissionRequest.self,
                    from: data
                )
                let response = try await delegate.handlePermissionRequest(decoded)
                let responseData = try encoder.encode(response)
                return try decoder.decode(AnyCodable.self, from: responseData)
            }

            if request.method == "elicitation/create" {
                guard let params = request.params else {
                    throw ClientError.invalidResponse
                }
                let encoder = JSONEncoder()
                let decoder = JSONDecoder()
                let data = try encoder.encode(params)
                let decoded = try decoder.decode(
                    ACPV2.CreateElicitationRequest.self,
                    from: data
                )
                let response = try await delegate.handleElicitationRequest(decoded)
                let responseData = try encoder.encode(response)
                return try decoder.decode(AnyCodable.self, from: responseData)
            }

            return try await delegate.handleV2Request(
                method: request.method,
                params: request.params
            )
        }
    }

    public func launch(
        agentPath: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) async throws {
        try await base.launch(
            agentPath: agentPath,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }

    public func initialize(
        info: ACPV2.Implementation,
        capabilities: ACPV2.ClientCapabilities = ACPV2.ClientCapabilities(),
        timeout: TimeInterval? = nil
    ) async throws -> ACPV2.InitializeResponse {
        let outcome = try await initializeForNegotiation(
            info: info,
            capabilities: capabilities,
            timeout: timeout
        )
        guard case .v2(let response) = outcome else {
            if case .v1(let response) = outcome {
                throw ACPProtocolNegotiationError.unsupportedVersion(response.protocolVersion)
            }
            throw ACPProtocolNegotiationError.unsupportedVersion(1)
        }
        return response
    }

    func initializeForNegotiation(
        info: ACPV2.Implementation,
        capabilities: ACPV2.ClientCapabilities,
        timeout: TimeInterval?
    ) async throws -> ACPInitializeOutcome {
        guard !initialized else {
            throw ACPProtocolNegotiationError.alreadyInitialized
        }

        let request = ACPV2.InitializeRequest(info: info, capabilities: capabilities)
        let response = try await base.sendRequest(
            method: "initialize",
            params: request,
            timeout: timeout
        )
        if let error = response.error {
            throw ClientError.agentError(error)
        }
        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let resultData = try encoder.encode(result)
        let version = try decoder.decode(ProtocolVersionResponse.self, from: resultData)
            .protocolVersion

        switch version {
        case 2:
            let decoded = try decoder.decode(ACPV2.InitializeResponse.self, from: resultData)
            initialized = true
            startUpdateForwarding()
            return .v2(decoded)
        case 1:
            let decoded = try decoder.decode(InitializeResponse.self, from: resultData)
            return .v1(decoded)
        default:
            throw ACPProtocolNegotiationError.unsupportedVersion(version)
        }
    }

    public func login(
        methodId: ACPV2.AuthMethodId,
        timeout: TimeInterval? = nil
    ) async throws -> ACPV2.LoginAuthResponse {
        try requireInitialized()
        return try await request(
            "auth/login",
            ACPV2.LoginAuthRequest(methodId: methodId),
            as: ACPV2.LoginAuthResponse.self,
            timeout: timeout
        )
    }

    public func logout(timeout: TimeInterval? = nil) async throws -> ACPV2.LogoutAuthResponse {
        try requireInitialized()
        return try await request(
            "auth/logout",
            ACPV2.LogoutAuthRequest(),
            as: ACPV2.LogoutAuthResponse.self,
            timeout: timeout
        )
    }

    public func newSession(
        _ request: ACPV2.NewSessionRequest,
        timeout: TimeInterval? = nil
    ) async throws -> ACPV2.NewSessionResponse {
        try requireInitialized()
        return try await self.request(
            "session/new",
            request,
            as: ACPV2.NewSessionResponse.self,
            timeout: timeout
        )
    }

    public func resumeSession(
        _ request: ACPV2.ResumeSessionRequest,
        timeout: TimeInterval? = nil
    ) async throws -> ACPV2.ResumeSessionResponse {
        try requireInitialized()
        return try await self.request(
            "session/resume",
            request,
            as: ACPV2.ResumeSessionResponse.self,
            timeout: timeout
        )
    }

    public func listSessions(
        _ request: ACPV2.ListSessionsRequest = ACPV2.ListSessionsRequest(),
        timeout: TimeInterval? = nil
    ) async throws -> ACPV2.ListSessionsResponse {
        try requireInitialized()
        return try await self.request(
            "session/list",
            request,
            as: ACPV2.ListSessionsResponse.self,
            timeout: timeout
        )
    }

    public func closeSession(
        sessionId: ACPV2.SessionId,
        timeout: TimeInterval? = nil
    ) async throws -> ACPV2.CloseSessionResponse {
        try requireInitialized()
        return try await request(
            "session/close",
            ACPV2.CloseSessionRequest(sessionId: sessionId),
            as: ACPV2.CloseSessionResponse.self,
            timeout: timeout
        )
    }

    public func deleteSession(
        sessionId: ACPV2.SessionId,
        timeout: TimeInterval? = nil
    ) async throws -> ACPV2.DeleteSessionResponse {
        try requireInitialized()
        return try await request(
            "session/delete",
            ACPV2.DeleteSessionRequest(sessionId: sessionId),
            as: ACPV2.DeleteSessionResponse.self,
            timeout: timeout
        )
    }

    public func setConfigOption(
        _ request: ACPV2.SetSessionConfigOptionRequest,
        timeout: TimeInterval? = nil
    ) async throws -> ACPV2.SetSessionConfigOptionResponse {
        try requireInitialized()
        return try await self.request(
            "session/set_config_option",
            request,
            as: ACPV2.SetSessionConfigOptionResponse.self,
            timeout: timeout
        )
    }

    /// Sends a prompt and returns when the v2 Agent accepts it.
    ///
    /// Completion is delivered later through an idle state update in `updates`.
    public func sendPrompt(
        _ request: ACPV2.PromptRequest,
        timeout: TimeInterval? = nil
    ) async throws -> ACPV2.PromptResponse {
        try requireInitialized()
        return try await self.request(
            "session/prompt",
            request,
            as: ACPV2.PromptResponse.self,
            timeout: timeout
        )
    }

    public func cancelSession(sessionId: ACPV2.SessionId) async throws {
        try requireInitialized()
        try await base.sendNotification(
            method: "session/cancel",
            params: ACPV2.CancelSessionNotification(sessionId: sessionId)
        )
    }

    public func sendCancelRequest(requestId: RequestId) async throws {
        try requireInitialized()
        try await base.sendCancelRequest(requestId: requestId)
    }

    public func processIdentifier() async -> Int32? {
        await base.processIdentifier()
    }

    public func processGroupIdentifier() async -> Int32? {
        await base.processGroupIdentifier()
    }

    public func stderrLines() async -> AsyncStream<String>? {
        await base.stderrLines()
    }

    public func terminate() async {
        updateTask?.cancel()
        updateTask = nil
        updateContinuation.finish()
        initialized = false
        await base.terminate()
    }

    private func request<Params: Encodable, Response: Decodable>(
        _ method: String,
        _ params: Params,
        as type: Response.Type,
        timeout: TimeInterval?
    ) async throws -> Response {
        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)
        let response = try await base.sendRequest(
            method: method,
            params: paramsValue,
            timeout: timeout
        )
        if let error = response.error {
            throw ClientError.agentError(error)
        }

        if response.result == nil || response.result?.value is NSNull {
            return try decoder.decode(type, from: Data("{}".utf8))
        }
        guard let result = response.result else {
            throw ClientError.invalidResponse
        }
        let data = try encoder.encode(result)
        return try decoder.decode(type, from: data)
    }

    private func requireInitialized() throws {
        guard initialized else {
            throw ACPProtocolNegotiationError.notInitialized
        }
    }

    private func startUpdateForwarding() {
        guard updateTask == nil else { return }
        let base = self.base
        let continuation = self.updateContinuation
        updateTask = Task { [weak self] in
            let notifications = await base.notifications
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            for await notification in notifications {
                guard !Task.isCancelled else { return }
                guard let params = notification.params,
                      let data = try? encoder.encode(params) else {
                    continue
                }

                if notification.method == "session/update",
                   let update = try? decoder.decode(
                        ACPV2.SessionUpdateNotification.self,
                        from: data
                   ) {
                    continuation.yield(update)
                } else if notification.method == "elicitation/complete",
                          let completed = try? decoder.decode(
                            ACPV2.CompleteElicitationNotification.self,
                            from: data
                          ) {
                    await self?.notifyElicitationComplete(completed)
                }
            }
        }
    }

    private func notifyElicitationComplete(
        _ notification: ACPV2.CompleteElicitationNotification
    ) async {
        try? await delegate?.handleElicitationComplete(notification)
    }

    private struct ProtocolVersionResponse: Decodable {
        let protocolVersion: Int
    }
}

public enum NegotiatedACPClient: Sendable {
    case v1(client: Client, response: InitializeResponse)
    case v2(client: V2Client, response: ACPV2.InitializeResponse)
}

public enum ACPClientConnector {
    public static func connect(
        agentPath: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        selection: ACPProtocolSelection = .automatic,
        v1Capabilities: ClientCapabilities,
        v1Info: ClientInfo? = nil,
        v2Capabilities: ACPV2.ClientCapabilities = ACPV2.ClientCapabilities(),
        v2Info: ACPV2.Implementation,
        timeout: TimeInterval? = nil
    ) async throws -> NegotiatedACPClient {
        switch selection {
        case .v1:
            let client = Client()
            try await client.launch(
                agentPath: agentPath,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
            let response = try await client.initialize(
                capabilities: v1Capabilities,
                clientInfo: v1Info,
                timeout: timeout
            )
            return .v1(client: client, response: response)

        case .v2, .automatic:
            let client = V2Client()
            try await client.launch(
                agentPath: agentPath,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )

            do {
                let outcome = try await client.initializeForNegotiation(
                    info: v2Info,
                    capabilities: v2Capabilities,
                    timeout: timeout
                )
                switch outcome {
                case .v2(let response):
                    return .v2(client: client, response: response)
                case .v1(let response):
                    if selection == .v2 {
                        await client.terminate()
                        throw ACPProtocolNegotiationError.unsupportedVersion(
                            response.protocolVersion
                        )
                    }

                    let requestedV1Initialize = InitializeRequest(
                        protocolVersion: 1,
                        clientCapabilities: v1Capabilities,
                        clientInfo: v1Info ?? defaultV1ClientInfo()
                    )
                    let normalizedV2Initialize = normalizedV1InitializeRequest(
                        from: ACPV2.InitializeRequest(
                            info: v2Info,
                            capabilities: v2Capabilities
                        )
                    )
                    if try canonicalJSON(requestedV1Initialize)
                        == canonicalJSON(normalizedV2Initialize)
                    {
                        return .v1(client: client.base, response: response)
                    }

                    await client.terminate()
                    let v1Client = Client()
                    try await v1Client.launch(
                        agentPath: agentPath,
                        arguments: arguments,
                        workingDirectory: workingDirectory,
                        environment: environment
                    )
                    do {
                        let v1Response = try await v1Client.initialize(
                            capabilities: v1Capabilities,
                            clientInfo: v1Info,
                            timeout: timeout
                        )
                        return .v1(client: v1Client, response: v1Response)
                    } catch {
                        await v1Client.terminate()
                        throw error
                    }
                }
            } catch {
                await client.terminate()
                throw error
            }
        }
    }

    private static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

func normalizedV1InitializeRequest(
    from request: ACPV2.InitializeRequest
) -> InitializeRequest {
    let elicitation = request.capabilities.elicitation.map {
        ElicitationCapabilities(
            form: $0.form.map { ElicitationFormCapabilities(_meta: $0._meta) },
            url: $0.url.map { ElicitationUrlCapabilities(_meta: $0._meta) },
            _meta: $0._meta
        )
    }
    let capabilities = ClientCapabilities(
        fs: FileSystemCapabilities(readTextFile: false, writeTextFile: false),
        terminal: false,
        meta: request.capabilities._meta,
        session: ClientSessionCapabilities(
            configOptions: SessionConfigOptionsCapabilities(
                boolean: BooleanConfigOptionCapabilities()
            )
        ),
        elicitation: elicitation
    )
    return InitializeRequest(
        protocolVersion: 1,
        clientCapabilities: capabilities,
        clientInfo: ClientInfo(
            name: request.info.name,
            title: request.info.title,
            version: request.info.version,
            _meta: request.info._meta
        ),
        _meta: request._meta
    )
}

private func defaultV1ClientInfo() -> ClientInfo {
    ClientInfo(name: "ACP", title: "ACP Client", version: "1.0.0")
}
