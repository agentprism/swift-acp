//
//  V2Core.swift
//  ACPModel
//
//  Experimental Agent Client Protocol v2 core types.
//

import Foundation

func encodeV2RawObject(
    _ fields: ACPV2.Meta,
    discriminator: String,
    value: String,
    to encoder: Encoder
) throws {
    var object = fields
    object[discriminator] = AnyCodable(value)
    try object.encode(to: encoder)
}

func decodeV2Patch<Key: CodingKey, Value: Decodable & Sendable>(
    _ type: Value.Type,
    forKey key: Key,
    from container: KeyedDecodingContainer<Key>
) throws -> ACPV2.Patch<Value> {
    guard container.contains(key) else {
        return .unchanged
    }
    if try container.decodeNil(forKey: key) {
        return .clear
    }
    return .value(try container.decode(type, forKey: key))
}

func encodeV2Patch<Key: CodingKey, Value: Encodable & Sendable>(
    _ patch: ACPV2.Patch<Value>,
    forKey key: Key,
    to container: inout KeyedEncodingContainer<Key>
) throws {
    switch patch {
    case .unchanged:
        break
    case .clear:
        try container.encodeNil(forKey: key)
    case .value(let value):
        try container.encode(value, forKey: key)
    }
}

/// Experimental ACP v2 schema namespace.
///
/// ACP v2 is a draft protocol. Its types intentionally live beside, rather
/// than replace, the stable v1 model surface.
public enum ACPV2 {
    public static let protocolVersion = 2

    public typealias Meta = [String: AnyCodable]
    public typealias SessionId = String
    public typealias SessionListCursor = String
    public typealias MessageId = String
    public typealias ToolCallId = String
    public typealias TerminalId = String
    public typealias PlanId = String
    public typealias SessionConfigId = String
    public typealias SessionConfigValueId = String
    public typealias SessionConfigGroupId = String
    public typealias PermissionOptionId = String
    public typealias AuthMethodId = String
    public typealias ElicitationId = String
    public typealias AbsolutePath = String
    public typealias MediaType = String

    /// A field with ACP v2 patch semantics.
    ///
    /// `.unchanged` encodes as an omitted field, `.clear` as `null`, and
    /// `.value` as a concrete replacement.
    public enum Patch<Value: Sendable>: Sendable {
        case unchanged
        case clear
        case value(Value)
    }

    /// An empty ACP result or support marker.
    public struct Empty: Codable, Sendable {
        public let _meta: Meta?

        public init(_meta: Meta? = nil) {
            self._meta = _meta
        }
    }

    /// A future-compatible string enum whose well-known values are scoped by
    /// a zero-sized tag type.
    public struct StringEnum<Tag: Sendable>: RawRepresentable, Codable, Hashable, Sendable,
        ExpressibleByStringLiteral, CustomStringConvertible
    {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }

        public var description: String { rawValue }
    }

    public struct Implementation: Codable, Sendable {
        public let name: String
        public let title: String?
        public let version: String
        public let _meta: Meta?

        public init(
            name: String,
            title: String? = nil,
            version: String,
            _meta: Meta? = nil
        ) {
            self.name = name
            self.title = title
            self.version = version
            self._meta = _meta
        }
    }
}

// MARK: - Capabilities and initialization

extension ACPV2 {
    public struct ClientCapabilities: Codable, Sendable {
        public let elicitation: ElicitationCapabilities?
        public let _meta: Meta?

        public init(elicitation: ElicitationCapabilities? = nil, _meta: Meta? = nil) {
            self.elicitation = elicitation
            self._meta = _meta
        }
    }

    public struct AgentCapabilities: Codable, Sendable {
        public let session: SessionCapabilities?
        public let auth: AgentAuthCapabilities?
        public let _meta: Meta?

        public init(
            session: SessionCapabilities? = nil,
            auth: AgentAuthCapabilities? = nil,
            _meta: Meta? = nil
        ) {
            self.session = session
            self.auth = auth
            self._meta = _meta
        }
    }

    public struct AgentAuthCapabilities: Codable, Sendable {
        public let _meta: Meta?

        public init(_meta: Meta? = nil) {
            self._meta = _meta
        }
    }

    public struct SessionCapabilities: Codable, Sendable {
        public let prompt: PromptCapabilities?
        public let mcp: MCPCapabilities?
        public let delete: Empty?
        public let additionalDirectories: Empty?
        public let _meta: Meta?

        public init(
            prompt: PromptCapabilities? = nil,
            mcp: MCPCapabilities? = nil,
            delete: Empty? = nil,
            additionalDirectories: Empty? = nil,
            _meta: Meta? = nil
        ) {
            self.prompt = prompt
            self.mcp = mcp
            self.delete = delete
            self.additionalDirectories = additionalDirectories
            self._meta = _meta
        }
    }

    public struct PromptCapabilities: Codable, Sendable {
        public let image: Empty?
        public let audio: Empty?
        public let embeddedContext: Empty?
        public let _meta: Meta?

        public init(
            image: Empty? = nil,
            audio: Empty? = nil,
            embeddedContext: Empty? = nil,
            _meta: Meta? = nil
        ) {
            self.image = image
            self.audio = audio
            self.embeddedContext = embeddedContext
            self._meta = _meta
        }
    }

    public struct MCPCapabilities: Codable, Sendable {
        public let stdio: Empty?
        public let http: Empty?
        public let _meta: Meta?

        public init(stdio: Empty? = nil, http: Empty? = nil, _meta: Meta? = nil) {
            self.stdio = stdio
            self.http = http
            self._meta = _meta
        }
    }

    public struct ElicitationCapabilities: Codable, Sendable {
        public let form: Empty?
        public let url: Empty?
        public let _meta: Meta?

        public init(form: Empty? = nil, url: Empty? = nil, _meta: Meta? = nil) {
            self.form = form
            self.url = url
            self._meta = _meta
        }
    }

    public struct InitializeRequest: Codable, Sendable {
        public let protocolVersion: Int
        public let info: Implementation
        public let capabilities: ClientCapabilities
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case protocolVersion
            case info
            case capabilities
            case _meta
        }

        public init(
            info: Implementation,
            capabilities: ClientCapabilities = ClientCapabilities(),
            _meta: Meta? = nil
        ) {
            self.protocolVersion = ACPV2.protocolVersion
            self.info = info
            self.capabilities = capabilities
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
            info = try container.decode(Implementation.self, forKey: .info)
            capabilities = try container.decodeIfPresent(
                ClientCapabilities.self,
                forKey: .capabilities
            ) ?? ClientCapabilities()
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }
    }

    public struct InitializeResponse: Codable, Sendable {
        public let protocolVersion: Int
        public let info: Implementation
        public let capabilities: AgentCapabilities
        public let authMethods: [AuthMethod]
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case protocolVersion
            case info
            case capabilities
            case authMethods
            case _meta
        }

        public init(
            info: Implementation,
            capabilities: AgentCapabilities = AgentCapabilities(),
            authMethods: [AuthMethod] = [],
            _meta: Meta? = nil
        ) {
            self.protocolVersion = ACPV2.protocolVersion
            self.info = info
            self.capabilities = capabilities
            self.authMethods = authMethods
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
            info = try container.decode(Implementation.self, forKey: .info)
            capabilities = try container.decodeIfPresent(
                AgentCapabilities.self,
                forKey: .capabilities
            ) ?? AgentCapabilities()
            authMethods = try container.decodeIfPresent(
                [AuthMethod].self,
                forKey: .authMethods
            ) ?? []
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }
    }

    public struct AuthMethod: Codable, Sendable {
        public let type: String
        public let methodId: AuthMethodId
        public let name: String
        public let description: String?
        public let _meta: Meta?
        public let additionalFields: Meta

        private enum CodingKeys: String, CodingKey {
            case type
            case methodId
            case name
            case description
            case _meta
        }

        public init(
            type: String = "agent",
            methodId: AuthMethodId,
            name: String,
            description: String? = nil,
            _meta: Meta? = nil,
            additionalFields: Meta = [:]
        ) {
            self.type = type
            self.methodId = methodId
            self.name = name
            self.description = description
            self._meta = _meta
            self.additionalFields = additionalFields
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            methodId = try container.decode(AuthMethodId.self, forKey: .methodId)
            name = try container.decode(String.self, forKey: .name)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)

            var fields = try decoder.singleValueContainer().decode(Meta.self)
            for key in ["type", "methodId", "name", "description", "_meta"] {
                fields.removeValue(forKey: key)
            }
            additionalFields = fields
        }

        public func encode(to encoder: Encoder) throws {
            var object = additionalFields
            object["type"] = AnyCodable(type)
            object["methodId"] = AnyCodable(methodId)
            object["name"] = AnyCodable(name)
            if let description {
                object["description"] = AnyCodable(description)
            }
            if let _meta {
                object["_meta"] = AnyCodable(_meta)
            }
            try object.encode(to: encoder)
        }
    }

    public struct LoginAuthRequest: Codable, Sendable {
        public let methodId: AuthMethodId
        public let _meta: Meta?

        public init(methodId: AuthMethodId, _meta: Meta? = nil) {
            self.methodId = methodId
            self._meta = _meta
        }
    }

    public typealias LoginAuthResponse = Empty
    public typealias LogoutAuthRequest = Empty
    public typealias LogoutAuthResponse = Empty
}

// MARK: - Content

extension ACPV2 {
    public struct Annotations: Codable, Sendable {
        public let audience: [String]?
        public let lastModified: String?
        public let priority: Double?
        public let _meta: Meta?

        public init(
            audience: [String]? = nil,
            lastModified: String? = nil,
            priority: Double? = nil,
            _meta: Meta? = nil
        ) {
            self.audience = audience
            self.lastModified = lastModified
            self.priority = priority
            self._meta = _meta
        }
    }

    public struct Icon: Codable, Sendable {
        public let src: String
        public let mimeType: MediaType?
        public let sizes: [String]?
        public let theme: String?

        public init(
            src: String,
            mimeType: MediaType? = nil,
            sizes: [String]? = nil,
            theme: String? = nil
        ) {
            self.src = src
            self.mimeType = mimeType
            self.sizes = sizes
            self.theme = theme
        }
    }

    public struct TextContent: Codable, Sendable {
        public let text: String
        public let annotations: Annotations?
        public let _meta: Meta?

        public init(text: String, annotations: Annotations? = nil, _meta: Meta? = nil) {
            self.text = text
            self.annotations = annotations
            self._meta = _meta
        }
    }

    public struct ImageContent: Codable, Sendable {
        public let data: String
        public let mimeType: MediaType
        public let uri: String?
        public let annotations: Annotations?
        public let _meta: Meta?

        public init(
            data: String,
            mimeType: MediaType,
            uri: String? = nil,
            annotations: Annotations? = nil,
            _meta: Meta? = nil
        ) {
            self.data = data
            self.mimeType = mimeType
            self.uri = uri
            self.annotations = annotations
            self._meta = _meta
        }
    }

    public struct AudioContent: Codable, Sendable {
        public let data: String
        public let mimeType: MediaType
        public let annotations: Annotations?
        public let _meta: Meta?

        public init(
            data: String,
            mimeType: MediaType,
            annotations: Annotations? = nil,
            _meta: Meta? = nil
        ) {
            self.data = data
            self.mimeType = mimeType
            self.annotations = annotations
            self._meta = _meta
        }
    }

    public struct ResourceLink: Codable, Sendable {
        public let name: String
        public let uri: String
        public let title: String?
        public let description: String?
        public let icons: [Icon]?
        public let mimeType: MediaType?
        public let size: Int64?
        public let annotations: Annotations?
        public let _meta: Meta?

        public init(
            name: String,
            uri: String,
            title: String? = nil,
            description: String? = nil,
            icons: [Icon]? = nil,
            mimeType: MediaType? = nil,
            size: Int64? = nil,
            annotations: Annotations? = nil,
            _meta: Meta? = nil
        ) {
            self.name = name
            self.uri = uri
            self.title = title
            self.description = description
            self.icons = icons
            self.mimeType = mimeType
            self.size = size
            self.annotations = annotations
            self._meta = _meta
        }
    }

    public struct TextResourceContents: Codable, Sendable {
        public let text: String
        public let uri: String
        public let mimeType: MediaType?
        public let _meta: Meta?

        public init(text: String, uri: String, mimeType: MediaType? = nil, _meta: Meta? = nil) {
            self.text = text
            self.uri = uri
            self.mimeType = mimeType
            self._meta = _meta
        }
    }

    public struct BlobResourceContents: Codable, Sendable {
        public let blob: String
        public let uri: String
        public let mimeType: MediaType?
        public let _meta: Meta?

        public init(blob: String, uri: String, mimeType: MediaType? = nil, _meta: Meta? = nil) {
            self.blob = blob
            self.uri = uri
            self.mimeType = mimeType
            self._meta = _meta
        }
    }

    public enum EmbeddedResourceContents: Codable, Sendable {
        case text(TextResourceContents)
        case blob(BlobResourceContents)

        private enum CodingKeys: String, CodingKey {
            case text
            case blob
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.text) {
                self = .text(try TextResourceContents(from: decoder))
            } else {
                self = .blob(try BlobResourceContents(from: decoder))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let value):
                try value.encode(to: encoder)
            case .blob(let value):
                try value.encode(to: encoder)
            }
        }
    }

    public struct EmbeddedResource: Codable, Sendable {
        public let resource: EmbeddedResourceContents
        public let annotations: Annotations?
        public let _meta: Meta?

        public init(
            resource: EmbeddedResourceContents,
            annotations: Annotations? = nil,
            _meta: Meta? = nil
        ) {
            self.resource = resource
            self.annotations = annotations
            self._meta = _meta
        }
    }

    public enum ContentBlock: Codable, Sendable {
        case text(TextContent)
        case image(ImageContent)
        case audio(AudioContent)
        case resourceLink(ResourceLink)
        case resource(EmbeddedResource)
        case other(type: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case type
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try TextContent(from: decoder))
            case "image":
                self = .image(try ImageContent(from: decoder))
            case "audio":
                self = .audio(try AudioContent(from: decoder))
            case "resource_link":
                self = .resourceLink(try ResourceLink(from: decoder))
            case "resource":
                self = .resource(try EmbeddedResource(from: decoder))
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
            default:
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let value):
                    try container.encode("text", forKey: .type)
                    try value.encode(to: encoder)
                case .image(let value):
                    try container.encode("image", forKey: .type)
                    try value.encode(to: encoder)
                case .audio(let value):
                    try container.encode("audio", forKey: .type)
                    try value.encode(to: encoder)
                case .resourceLink(let value):
                    try container.encode("resource_link", forKey: .type)
                    try value.encode(to: encoder)
                case .resource(let value):
                    try container.encode("resource", forKey: .type)
                    try value.encode(to: encoder)
                case .other:
                    break
                }
            }
        }
    }
}

// MARK: - MCP server configuration

extension ACPV2 {
    public struct EnvVariable: Codable, Sendable {
        public let name: String
        public let value: String
        public let _meta: Meta?

        public init(name: String, value: String, _meta: Meta? = nil) {
            self.name = name
            self.value = value
            self._meta = _meta
        }
    }

    public struct HTTPHeader: Codable, Sendable {
        public let name: String
        public let value: String
        public let _meta: Meta?

        public init(name: String, value: String, _meta: Meta? = nil) {
            self.name = name
            self.value = value
            self._meta = _meta
        }
    }

    public struct MCPServerStdio: Codable, Sendable {
        public let name: String
        public let command: AbsolutePath
        public let args: [String]
        public let env: [EnvVariable]
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case name
            case command
            case args
            case env
            case _meta
        }

        public init(
            name: String,
            command: AbsolutePath,
            args: [String] = [],
            env: [EnvVariable] = [],
            _meta: Meta? = nil
        ) {
            self.name = name
            self.command = command
            self.args = args
            self.env = env
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            command = try container.decode(AbsolutePath.self, forKey: .command)
            args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
            env = try container.decodeIfPresent([EnvVariable].self, forKey: .env) ?? []
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }
    }

    public struct MCPServerHTTP: Codable, Sendable {
        public let name: String
        public let url: String
        public let headers: [HTTPHeader]
        public let _meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case name
            case url
            case headers
            case _meta
        }

        public init(
            name: String,
            url: String,
            headers: [HTTPHeader] = [],
            _meta: Meta? = nil
        ) {
            self.name = name
            self.url = url
            self.headers = headers
            self._meta = _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            url = try container.decode(String.self, forKey: .url)
            headers = try container.decodeIfPresent(
                [HTTPHeader].self,
                forKey: .headers
            ) ?? []
            _meta = try container.decodeIfPresent(Meta.self, forKey: ._meta)
        }
    }

    public enum MCPServer: Codable, Sendable {
        case stdio(MCPServerStdio)
        case http(MCPServerHTTP)
        case other(type: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case type
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "stdio":
                self = .stdio(try MCPServerStdio(from: decoder))
            case "http":
                self = .http(try MCPServerHTTP(from: decoder))
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
            default:
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .stdio(let value):
                    try container.encode("stdio", forKey: .type)
                    try value.encode(to: encoder)
                case .http(let value):
                    try container.encode("http", forKey: .type)
                    try value.encode(to: encoder)
                case .other:
                    break
                }
            }
        }
    }
}
