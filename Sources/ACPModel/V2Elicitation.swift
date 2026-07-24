//
//  V2Elicitation.swift
//  ACPModel
//
//  ACP v2 elicitation types.
//

import Foundation

extension ACPV2 {
    public enum ElicitationScope: Codable, Sendable {
        case session(sessionId: SessionId, toolCallId: ToolCallId?)
        case request(requestId: RequestId)

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case toolCallId
            case requestId
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let sessionId = try container.decodeIfPresent(
                SessionId.self,
                forKey: .sessionId
            ) {
                self = .session(
                    sessionId: sessionId,
                    toolCallId: try container.decodeIfPresent(
                        ToolCallId.self,
                        forKey: .toolCallId
                    )
                )
                return
            }
            self = .request(
                requestId: try container.decode(RequestId.self, forKey: .requestId)
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .session(let sessionId, let toolCallId):
                try container.encode(sessionId, forKey: .sessionId)
                try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
            case .request(let requestId):
                try container.encode(requestId, forKey: .requestId)
            }
        }
    }

    /// JSON Schema object used for form elicitations.
    ///
    /// The schema remains open so future JSON Schema vocabulary can pass
    /// through without requiring a swift-acp release.
    public struct ElicitationSchema: Codable, Sendable {
        public let type: String
        public let title: String?
        public let properties: [String: Meta]
        public let required: [String]?
        public let description: String?
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case type
            case title
            case properties
            case required
            case description
            case _meta
        }

        public init(
            title: String? = nil,
            properties: [String: Meta] = [:],
            required: [String]? = nil,
            description: String? = nil,
            _meta: Meta? = nil
        ) {
            self.type = "object"
            self.title = title
            self.properties = properties
            self.required = required
            self.description = description
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(String.self, forKey: .type) ?? "object"
            title = try container.decodeIfPresent(String.self, forKey: .title)
            properties = try container.decodeIfPresent(
                [String: Meta].self,
                forKey: .properties
            ) ?? [:]
            required = try container.decodeIfPresent([String].self, forKey: .required)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }
    }

    public enum ElicitationMode: Codable, Sendable {
        case form(scope: ElicitationScope, requestedSchema: ElicitationSchema)
        case url(
            scope: ElicitationScope,
            elicitationId: ElicitationId,
            url: String
        )
        case other(mode: String, scope: ElicitationScope, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case mode
            case requestedSchema
            case elicitationId
            case url
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let mode = try container.decode(String.self, forKey: .mode)
            let scope = try ElicitationScope(from: decoder)
            switch mode {
            case "form":
                self = .form(
                    scope: scope,
                    requestedSchema: try container.decode(
                        ElicitationSchema.self,
                        forKey: .requestedSchema
                    )
                )
            case "url":
                self = .url(
                    scope: scope,
                    elicitationId: try container.decode(
                        ElicitationId.self,
                        forKey: .elicitationId
                    ),
                    url: try container.decode(String.self, forKey: .url)
                )
            default:
                self = .other(
                    mode: mode,
                    scope: scope,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            if case .other(let mode, let scope, let fields) = self {
                var object = fields
                object["mode"] = AnyCodable(mode)
                let scopeData = try JSONEncoder().encode(scope)
                let scopeObject = try JSONDecoder().decode(Meta.self, from: scopeData)
                object.merge(scopeObject) { _, new in new }
                try object.encode(to: encoder)
                return
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .form(let scope, let requestedSchema):
                try container.encode("form", forKey: .mode)
                try container.encode(requestedSchema, forKey: .requestedSchema)
                try scope.encode(to: encoder)
            case .url(let scope, let elicitationId, let url):
                try container.encode("url", forKey: .mode)
                try container.encode(elicitationId, forKey: .elicitationId)
                try container.encode(url, forKey: .url)
                try scope.encode(to: encoder)
            case .other:
                break
            }
        }
    }

    public struct CreateElicitationRequest: Codable, Sendable {
        public let mode: ElicitationMode
        public let message: String
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case message
            case _meta
        }

        public init(
            mode: ElicitationMode,
            message: String,
            _meta: Meta? = nil
        ) {
            self.mode = mode
            self.message = message
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = try ElicitationMode(from: decoder)
            message = try container.decode(String.self, forKey: .message)
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message, forKey: .message)
            try container.encodeIfPresent(_meta, forKey: ._meta)
            try mode.encode(to: encoder)
        }
    }

    public enum ElicitationContentValue: Codable, Sendable {
        case string(String)
        case integer(Int64)
        case number(Double)
        case boolean(Bool)
        case stringArray([String])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode(Bool.self) {
                self = .boolean(value)
            } else if let value = try? container.decode(Int64.self) {
                self = .integer(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else {
                self = .stringArray(try container.decode([String].self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .integer(let value):
                try container.encode(value)
            case .number(let value):
                try container.encode(value)
            case .boolean(let value):
                try container.encode(value)
            case .stringArray(let value):
                try container.encode(value)
            }
        }
    }

    public enum ElicitationAction: Codable, Sendable {
        case accept(content: [String: ElicitationContentValue]?)
        case decline
        case cancel
        case other(action: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case action
            case content
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let action = try container.decode(String.self, forKey: .action)
            switch action {
            case "accept":
                self = .accept(
                    content: try container.decodeIfPresent(
                        [String: ElicitationContentValue].self,
                        forKey: .content
                    )
                )
            case "decline":
                self = .decline
            case "cancel":
                self = .cancel
            default:
                self = .other(
                    action: action,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .other(let action, let fields):
                try encodeV2RawObject(
                    fields,
                    discriminator: "action",
                    value: action,
                    to: encoder
                )
            case .accept(let content):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("accept", forKey: .action)
                try container.encodeIfPresent(content, forKey: .content)
            case .decline:
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("decline", forKey: .action)
            case .cancel:
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("cancel", forKey: .action)
            }
        }
    }

    public struct CreateElicitationResponse: Codable, Sendable {
        public let action: ElicitationAction
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case _meta
        }

        public init(action: ElicitationAction, _meta: Meta? = nil) {
            self.action = action
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            action = try ElicitationAction(from: decoder)
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(_meta, forKey: ._meta)
            try action.encode(to: encoder)
        }
    }

    public struct CompleteElicitationNotification: Codable, Sendable {
        public let elicitationId: ElicitationId
        public let _meta: Meta?

        public init(elicitationId: ElicitationId, _meta: Meta? = nil) {
            self.elicitationId = elicitationId
            self._meta = _meta
        }
    }
}
