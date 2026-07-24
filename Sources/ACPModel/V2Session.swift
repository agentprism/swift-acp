//
//  V2Session.swift
//  ACPModel
//
//  Experimental ACP v2 session lifecycle types.
//

import Foundation

// MARK: - Session configuration

extension ACPV2 {
    public struct SessionConfigSelectOption: Codable, Sendable {
        public let value: SessionConfigValueId
        public let name: String
        public let description: String?
        public let _meta: Meta?

        public init(
            value: SessionConfigValueId,
            name: String,
            description: String? = nil,
            _meta: Meta? = nil
        ) {
            self.value = value
            self.name = name
            self.description = description
            self._meta = _meta
        }
    }

    public struct SessionConfigSelectGroup: Codable, Sendable {
        public let groupId: SessionConfigGroupId
        public let name: String
        public let options: [SessionConfigSelectOption]
        public let _meta: Meta?

        public init(
            groupId: SessionConfigGroupId,
            name: String,
            options: [SessionConfigSelectOption],
            _meta: Meta? = nil
        ) {
            self.groupId = groupId
            self.name = name
            self.options = options
            self._meta = _meta
        }
    }

    public enum SessionConfigSelectOptions: Codable, Sendable {
        case ungrouped([SessionConfigSelectOption])
        case grouped([SessionConfigSelectGroup])

        public init(from decoder: Decoder) throws {
            let array = try decoder.unkeyedContainer()
            if array.isAtEnd {
                self = .ungrouped([])
                return
            }

            let container = try decoder.singleValueContainer()
            if let groups = try? container.decode([SessionConfigSelectGroup].self) {
                self = .grouped(groups)
            } else {
                self = .ungrouped(try container.decode([SessionConfigSelectOption].self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .ungrouped(let options):
                try container.encode(options)
            case .grouped(let groups):
                try container.encode(groups)
            }
        }
    }

    public struct SessionConfigSelect: Codable, Sendable {
        public let currentValue: SessionConfigValueId
        public let options: SessionConfigSelectOptions

        public init(currentValue: SessionConfigValueId, options: SessionConfigSelectOptions) {
            self.currentValue = currentValue
            self.options = options
        }
    }

    public struct SessionConfigBoolean: Codable, Sendable {
        public let currentValue: Bool

        public init(currentValue: Bool) {
            self.currentValue = currentValue
        }
    }

    public struct SessionConfigOption: Codable, Sendable {
        public enum Kind: Sendable {
            case select(SessionConfigSelect)
            case boolean(SessionConfigBoolean)
            case other(type: String, fields: Meta)
        }

        public let configId: SessionConfigId
        public let name: String
        public let description: String?
        public let category: String?
        public let kind: Kind
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case configId
            case name
            case description
            case category
            case type
            case currentValue
            case options
            case _meta
        }

        public init(
            configId: SessionConfigId,
            name: String,
            description: String? = nil,
            category: String? = nil,
            kind: Kind,
            _meta: Meta? = nil
        ) {
            self.configId = configId
            self.name = name
            self.description = description
            self.category = category
            self.kind = kind
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            configId = try container.decode(SessionConfigId.self, forKey: .configId)
            name = try container.decode(String.self, forKey: .name)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            category = try container.decodeIfPresent(String.self, forKey: .category)
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)

            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "select":
                kind = .select(
                    SessionConfigSelect(
                        currentValue: try container.decode(
                            SessionConfigValueId.self,
                            forKey: .currentValue
                        ),
                        options: try container.decode(
                            SessionConfigSelectOptions.self,
                            forKey: .options
                        )
                    )
                )
            case "boolean":
                kind = .boolean(
                    SessionConfigBoolean(
                        currentValue: try container.decode(Bool.self, forKey: .currentValue)
                    )
                )
            default:
                kind = .other(
                    type: type,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            if case .other(let type, let fields) = kind {
                var object = fields
                object["configId"] = AnyCodable(configId)
                object["name"] = AnyCodable(name)
                if let description {
                    object["description"] = AnyCodable(description)
                }
                if let category {
                    object["category"] = AnyCodable(category)
                }
                if let _meta {
                    object["_meta"] = AnyCodable(_meta)
                }
                try encodeV2RawObject(object, discriminator: "type", value: type, to: encoder)
                return
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(configId, forKey: .configId)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(category, forKey: .category)
            try container.encodeIfPresent(_meta, forKey: ._meta)

            switch kind {
            case .select(let value):
                try container.encode("select", forKey: .type)
                try container.encode(value.currentValue, forKey: .currentValue)
                try container.encode(value.options, forKey: .options)
            case .boolean(let value):
                try container.encode("boolean", forKey: .type)
                try container.encode(value.currentValue, forKey: .currentValue)
            case .other:
                break
            }
        }
    }

    public enum SessionConfigValue: Codable, Sendable {
        case id(SessionConfigValueId)
        case boolean(Bool)
        case other(type: String, value: AnyCodable, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case type
            case value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "id":
                self = .id(try container.decode(SessionConfigValueId.self, forKey: .value))
            case "boolean":
                self = .boolean(try container.decode(Bool.self, forKey: .value))
            default:
                self = .other(
                    type: type,
                    value: try container.decode(AnyCodable.self, forKey: .value),
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .other(let type, let value, let fields):
                var object = fields
                object["value"] = value
                try encodeV2RawObject(object, discriminator: "type", value: type, to: encoder)
            case .id(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("id", forKey: .type)
                try container.encode(value, forKey: .value)
            case .boolean(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("boolean", forKey: .type)
                try container.encode(value, forKey: .value)
            }
        }
    }
}

// MARK: - Session lifecycle

extension ACPV2 {
    public struct NewSessionRequest: Codable, Sendable {
        public let cwd: AbsolutePath
        public let additionalDirectories: [AbsolutePath]
        public let mcpServers: [MCPServer]
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case cwd
            case additionalDirectories
            case mcpServers
            case _meta
        }

        public init(
            cwd: AbsolutePath,
            additionalDirectories: [AbsolutePath] = [],
            mcpServers: [MCPServer] = [],
            _meta: Meta? = nil
        ) {
            self.cwd = cwd
            self.additionalDirectories = additionalDirectories
            self.mcpServers = mcpServers
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cwd = try container.decode(AbsolutePath.self, forKey: .cwd)
            additionalDirectories = try container.decodeIfPresent(
                [AbsolutePath].self,
                forKey: .additionalDirectories
            ) ?? []
            mcpServers = try container.decodeIfPresent(
                [MCPServer].self,
                forKey: .mcpServers
            ) ?? []
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }
    }

    public struct NewSessionResponse: Codable, Sendable {
        public let sessionId: SessionId
        public let configOptions: [SessionConfigOption]
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case configOptions
            case _meta
        }

        public init(
            sessionId: SessionId,
            configOptions: [SessionConfigOption] = [],
            _meta: Meta? = nil
        ) {
            self.sessionId = sessionId
            self.configOptions = configOptions
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionId = try container.decode(SessionId.self, forKey: .sessionId)
            configOptions = try container.decodeIfPresent(
                [SessionConfigOption].self,
                forKey: .configOptions
            ) ?? []
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }
    }

    public enum ReplayFrom: Codable, Sendable {
        case start
        case other(type: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case type
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            if type == "start" {
                self = .start
            } else {
                self = .other(
                    type: type,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .start:
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("start", forKey: .type)
            case .other(let type, let fields):
                try encodeV2RawObject(fields, discriminator: "type", value: type, to: encoder)
            }
        }
    }

    public struct ResumeSessionRequest: Codable, Sendable {
        public let sessionId: SessionId
        public let cwd: AbsolutePath
        public let additionalDirectories: [AbsolutePath]
        public let mcpServers: [MCPServer]
        public let replayFrom: ReplayFrom?
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case cwd
            case additionalDirectories
            case mcpServers
            case replayFrom
            case _meta
        }

        public init(
            sessionId: SessionId,
            cwd: AbsolutePath,
            additionalDirectories: [AbsolutePath] = [],
            mcpServers: [MCPServer] = [],
            replayFrom: ReplayFrom? = nil,
            _meta: Meta? = nil
        ) {
            self.sessionId = sessionId
            self.cwd = cwd
            self.additionalDirectories = additionalDirectories
            self.mcpServers = mcpServers
            self.replayFrom = replayFrom
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionId = try container.decode(SessionId.self, forKey: .sessionId)
            cwd = try container.decode(AbsolutePath.self, forKey: .cwd)
            additionalDirectories = try container.decodeIfPresent(
                [AbsolutePath].self,
                forKey: .additionalDirectories
            ) ?? []
            mcpServers = try container.decodeIfPresent(
                [MCPServer].self,
                forKey: .mcpServers
            ) ?? []
            replayFrom = try container.decodeIfPresent(
                ReplayFrom.self,
                forKey: .replayFrom
            )
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }
    }

    public struct ResumeSessionResponse: Codable, Sendable {
        public let configOptions: [SessionConfigOption]
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case configOptions
            case _meta
        }

        public init(configOptions: [SessionConfigOption] = [], _meta: Meta? = nil) {
            self.configOptions = configOptions
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            configOptions = try container.decodeIfPresent(
                [SessionConfigOption].self,
                forKey: .configOptions
            ) ?? []
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }
    }

    public struct SessionInfo: Codable, Sendable {
        public let sessionId: SessionId
        public let cwd: AbsolutePath
        public let additionalDirectories: [AbsolutePath]
        public let title: String?
        public let updatedAt: String?
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case cwd
            case additionalDirectories
            case title
            case updatedAt
            case _meta
        }

        public init(
            sessionId: SessionId,
            cwd: AbsolutePath,
            additionalDirectories: [AbsolutePath] = [],
            title: String? = nil,
            updatedAt: String? = nil,
            _meta: Meta? = nil
        ) {
            self.sessionId = sessionId
            self.cwd = cwd
            self.additionalDirectories = additionalDirectories
            self.title = title
            self.updatedAt = updatedAt
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionId = try container.decode(SessionId.self, forKey: .sessionId)
            cwd = try container.decode(AbsolutePath.self, forKey: .cwd)
            additionalDirectories = try container.decodeIfPresent(
                [AbsolutePath].self,
                forKey: .additionalDirectories
            ) ?? []
            title = try container.decodeIfPresent(String.self, forKey: .title)
            updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }
    }

    public struct ListSessionsRequest: Codable, Sendable {
        public let cwd: AbsolutePath?
        public let cursor: SessionListCursor?
        public let _meta: Meta?

        public init(
            cwd: AbsolutePath? = nil,
            cursor: SessionListCursor? = nil,
            _meta: Meta? = nil
        ) {
            self.cwd = cwd
            self.cursor = cursor
            self._meta = _meta
        }
    }

    public struct ListSessionsResponse: Codable, Sendable {
        public let sessions: [SessionInfo]
        public let nextCursor: SessionListCursor?
        public let _meta: Meta?

        public init(
            sessions: [SessionInfo],
            nextCursor: SessionListCursor? = nil,
            _meta: Meta? = nil
        ) {
            self.sessions = sessions
            self.nextCursor = nextCursor
            self._meta = _meta
        }
    }

    public struct SessionIdRequest: Codable, Sendable {
        public let sessionId: SessionId
        public let _meta: Meta?

        public init(sessionId: SessionId, _meta: Meta? = nil) {
            self.sessionId = sessionId
            self._meta = _meta
        }
    }

    public typealias CloseSessionRequest = SessionIdRequest
    public typealias CloseSessionResponse = Empty
    public typealias DeleteSessionRequest = SessionIdRequest
    public typealias DeleteSessionResponse = Empty
    public typealias CancelSessionNotification = SessionIdRequest

    public struct SetSessionConfigOptionRequest: Codable, Sendable {
        public let sessionId: SessionId
        public let configId: SessionConfigId
        public let value: SessionConfigValue
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case configId
            case type
            case value
            case _meta
        }

        public init(
            sessionId: SessionId,
            configId: SessionConfigId,
            value: SessionConfigValue,
            _meta: Meta? = nil
        ) {
            self.sessionId = sessionId
            self.configId = configId
            self.value = value
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionId = try container.decode(SessionId.self, forKey: .sessionId)
            configId = try container.decode(SessionConfigId.self, forKey: .configId)
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
            value = try SessionConfigValue(from: decoder)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(configId, forKey: .configId)
            try container.encodeIfPresent(_meta, forKey: ._meta)
            try value.encode(to: encoder)
        }
    }

    public struct SetSessionConfigOptionResponse: Codable, Sendable {
        public let configOptions: [SessionConfigOption]
        public let _meta: Meta?

        public init(configOptions: [SessionConfigOption], _meta: Meta? = nil) {
            self.configOptions = configOptions
            self._meta = _meta
        }
    }

    public struct PromptRequest: Codable, Sendable {
        public let sessionId: SessionId
        public let prompt: [ContentBlock]
        public let _meta: Meta?

        public init(sessionId: SessionId, prompt: [ContentBlock], _meta: Meta? = nil) {
            self.sessionId = sessionId
            self.prompt = prompt
            self._meta = _meta
        }
    }

    public typealias PromptResponse = Empty
}

// MARK: - Permission requests

extension ACPV2 {
    public struct PermissionOption: Codable, Sendable {
        public let optionId: PermissionOptionId
        public let name: String
        public let kind: String
        public let _meta: Meta?

        public init(
            optionId: PermissionOptionId,
            name: String,
            kind: String,
            _meta: Meta? = nil
        ) {
            self.optionId = optionId
            self.name = name
            self.kind = kind
            self._meta = _meta
        }
    }

    public struct CommandPermissionSubject: Codable, Sendable {
        public let command: String
        public let cwd: AbsolutePath
        public let toolCallId: ToolCallId?
        public let terminalId: TerminalId?
        public let _meta: Meta?

        public init(
            command: String,
            cwd: AbsolutePath,
            toolCallId: ToolCallId? = nil,
            terminalId: TerminalId? = nil,
            _meta: Meta? = nil
        ) {
            self.command = command
            self.cwd = cwd
            self.toolCallId = toolCallId
            self.terminalId = terminalId
            self._meta = _meta
        }
    }

    public enum RequestPermissionSubject: Codable, Sendable {
        case toolCall(ToolCallUpdate)
        case command(CommandPermissionSubject)
        case other(type: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case type
            case toolCall
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "tool_call":
                self = .toolCall(try container.decode(ToolCallUpdate.self, forKey: .toolCall))
            case "command":
                self = .command(try CommandPermissionSubject(from: decoder))
            default:
                self = .other(
                    type: type,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .other(let type, let fields):
                try encodeV2RawObject(fields, discriminator: "type", value: type, to: encoder)
            case .toolCall(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("tool_call", forKey: .type)
                try container.encode(value, forKey: .toolCall)
            case .command(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("command", forKey: .type)
                try value.encode(to: encoder)
            }
        }
    }

    public struct RequestPermissionRequest: Codable, Sendable {
        public let sessionId: SessionId
        public let title: String
        public let description: String?
        public let subject: RequestPermissionSubject?
        public let options: [PermissionOption]
        public let _meta: Meta?

        public init(
            sessionId: SessionId,
            title: String,
            description: String? = nil,
            subject: RequestPermissionSubject? = nil,
            options: [PermissionOption],
            _meta: Meta? = nil
        ) {
            self.sessionId = sessionId
            self.title = title
            self.description = description
            self.subject = subject
            self.options = options
            self._meta = _meta
        }
    }

    public enum RequestPermissionOutcome: Codable, Sendable {
        case cancelled
        case selected(PermissionOptionId)
        case other(outcome: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case outcome
            case optionId
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let outcome = try container.decode(String.self, forKey: .outcome)
            switch outcome {
            case "cancelled":
                self = .cancelled
            case "selected":
                self = .selected(try container.decode(PermissionOptionId.self, forKey: .optionId))
            default:
                self = .other(
                    outcome: outcome,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .other(let outcome, let fields):
                try encodeV2RawObject(
                    fields,
                    discriminator: "outcome",
                    value: outcome,
                    to: encoder
                )
            case .cancelled:
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("cancelled", forKey: .outcome)
            case .selected(let optionId):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("selected", forKey: .outcome)
                try container.encode(optionId, forKey: .optionId)
            }
        }
    }

    public struct RequestPermissionResponse: Codable, Sendable {
        public let outcome: RequestPermissionOutcome
        public let _meta: Meta?

        public init(outcome: RequestPermissionOutcome, _meta: Meta? = nil) {
            self.outcome = outcome
            self._meta = _meta
        }
    }
}
