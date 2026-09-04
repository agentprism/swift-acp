//
//  Permission.swift
//  ACPModel
//
//  Agent Client Protocol - Permission Types
//

import Foundation

// MARK: - Permission Request

public struct RequestPermissionRequest: Codable, Sendable {
    public let options: [PermissionOption]
    public let sessionId: SessionId
    public let toolCall: ToolCallUpdate
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case options
        case sessionId
        case toolCall
        case _meta
    }

    public init(
        options: [PermissionOption],
        sessionId: SessionId,
        toolCall: ToolCallUpdate,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.options = options
        self.sessionId = sessionId
        self.toolCall = toolCall
        self._meta = _meta
    }
}

public struct PermissionOption: Codable, Sendable {
    public let kind: String
    public let name: String
    public let optionId: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case kind
        case name
        case optionId
        case _meta
    }

    public init(
        kind: String,
        name: String,
        optionId: String,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.kind = kind
        self.name = name
        self.optionId = optionId
        self._meta = _meta
    }
}

// MARK: - Permission Decision

public enum PermissionDecision: String, Codable, Sendable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case rejectOnce = "reject_once"
    case rejectAlways = "reject_always"
}

// MARK: - Permission Response

public struct RequestPermissionResponse: Codable, Sendable {
    public let outcome: PermissionOutcome
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case outcome
        case _meta
    }

    public init(
        outcome: PermissionOutcome,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.outcome = outcome
        self._meta = _meta
    }
}

public struct PermissionOutcome: Codable, Sendable {
    public let outcome: String
    public let optionId: String?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case outcome
        case optionId
        case _meta
    }

    public init(optionId: String, _meta: [String: AnyCodable]? = nil) {
        outcome = "selected"
        self.optionId = optionId
        self._meta = _meta
    }

    public init(cancelled _: Bool, _meta: [String: AnyCodable]? = nil) {
        outcome = "cancelled"
        optionId = nil
        self._meta = _meta
    }
}
