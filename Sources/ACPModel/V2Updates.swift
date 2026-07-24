//
//  V2Updates.swift
//  ACPModel
//
//  Experimental ACP v2 session update types.
//

import Foundation

// MARK: - Future-compatible value families

extension ACPV2 {
    public enum StopReasonTag: Sendable {}
    public typealias StopReason = StringEnum<StopReasonTag>

    public enum ToolKindTag: Sendable {}
    public typealias ToolKind = StringEnum<ToolKindTag>

    public enum ToolCallStatusTag: Sendable {}
    public typealias ToolCallStatus = StringEnum<ToolCallStatusTag>

    public enum PlanEntryPriorityTag: Sendable {}
    public typealias PlanEntryPriority = StringEnum<PlanEntryPriorityTag>

    public enum PlanEntryStatusTag: Sendable {}
    public typealias PlanEntryStatus = StringEnum<PlanEntryStatusTag>

    public enum DiffFileTypeTag: Sendable {}
    public typealias DiffFileType = StringEnum<DiffFileTypeTag>

    public enum DiffPatchFormatTag: Sendable {}
    public typealias DiffPatchFormat = StringEnum<DiffPatchFormatTag>
}

extension ACPV2.StringEnum where Tag == ACPV2.StopReasonTag {
    public static let endTurn: Self = "end_turn"
    public static let maxTokens: Self = "max_tokens"
    public static let maxTurnRequests: Self = "max_turn_requests"
    public static let refusal: Self = "refusal"
    public static let cancelled: Self = "cancelled"
}

extension ACPV2.StringEnum where Tag == ACPV2.ToolCallStatusTag {
    public static let pending: Self = "pending"
    public static let inProgress: Self = "in_progress"
    public static let completed: Self = "completed"
    public static let failed: Self = "failed"
    public static let cancelled: Self = "cancelled"
}

extension ACPV2.StringEnum where Tag == ACPV2.PlanEntryPriorityTag {
    public static let high: Self = "high"
    public static let medium: Self = "medium"
    public static let low: Self = "low"
}

extension ACPV2.StringEnum where Tag == ACPV2.PlanEntryStatusTag {
    public static let pending: Self = "pending"
    public static let inProgress: Self = "in_progress"
    public static let completed: Self = "completed"
}

// MARK: - Messages and state

extension ACPV2 {
    public struct ContentChunk: Codable, Sendable {
        public let messageId: MessageId
        public let content: ContentBlock
        public let _meta: Meta?

        public init(messageId: MessageId, content: ContentBlock, _meta: Meta? = nil) {
            self.messageId = messageId
            self.content = content
            self._meta = _meta
        }
    }

    public struct MessageUpdate: Codable, Sendable {
        public let messageId: MessageId
        public let content: Patch<[ContentBlock]>
        public let meta: Patch<Meta>

        private enum CodingKeys: String, CodingKey {
            case messageId
            case content
            case _meta
        }

        public init(
            messageId: MessageId,
            content: Patch<[ContentBlock]> = .unchanged,
            meta: Patch<Meta> = .unchanged
        ) {
            self.messageId = messageId
            self.content = content
            self.meta = meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            messageId = try container.decode(MessageId.self, forKey: .messageId)
            content = try decodeV2Patch([ContentBlock].self, forKey: .content, from: container)
            meta = try decodeV2Patch(Meta.self, forKey: ._meta, from: container)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(messageId, forKey: .messageId)
            try encodeV2Patch(content, forKey: .content, to: &container)
            try encodeV2Patch(meta, forKey: ._meta, to: &container)
        }
    }

    public enum StateUpdate: Codable, Sendable {
        case running(meta: Meta? = nil)
        case idle(stopReason: StopReason? = nil, meta: Meta? = nil)
        case requiresAction(meta: Meta? = nil)
        case other(state: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case state
            case stopReason
            case _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let state = try container.decode(String.self, forKey: .state)
            switch state {
            case "running":
                self = .running(meta: try container.decodeIfPresent(Meta.self, forKey: ._meta))
            case "idle":
                self = .idle(
                    stopReason: try container.decodeIfPresent(StopReason.self, forKey: .stopReason),
                    meta: try container.decodeIfPresent(Meta.self, forKey: ._meta)
                )
            case "requires_action":
                self = .requiresAction(
                    meta: try container.decodeIfPresent(Meta.self, forKey: ._meta)
                )
            default:
                self = .other(
                    state: state,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .other(let state, let fields):
                try encodeV2RawObject(
                    fields,
                    discriminator: "state",
                    value: state,
                    to: encoder
                )
            case .running(let meta):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("running", forKey: .state)
                try container.encodeIfPresent(meta, forKey: ._meta)
            case .idle(let stopReason, let meta):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("idle", forKey: .state)
                try container.encodeIfPresent(stopReason, forKey: .stopReason)
                try container.encodeIfPresent(meta, forKey: ._meta)
            case .requiresAction(let meta):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("requires_action", forKey: .state)
                try container.encodeIfPresent(meta, forKey: ._meta)
            }
        }
    }
}

// MARK: - Tool calls and diffs

extension ACPV2 {
    public struct ToolCallLocation: Codable, Sendable {
        public let path: AbsolutePath
        public let line: UInt32?
        public let _meta: Meta?

        public init(path: AbsolutePath, line: UInt32? = nil, _meta: Meta? = nil) {
            self.path = path
            self.line = line
            self._meta = _meta
        }
    }

    public struct DiffPathMetadata: Codable, Sendable {
        public let fileType: DiffFileType?
        public let mimeType: MediaType?
        public let _meta: Meta?

        public init(
            fileType: DiffFileType? = nil,
            mimeType: MediaType? = nil,
            _meta: Meta? = nil
        ) {
            self.fileType = fileType
            self.mimeType = mimeType
            self._meta = _meta
        }
    }

    public enum DiffChange: Codable, Sendable {
        case add(path: AbsolutePath, metadata: DiffPathMetadata = DiffPathMetadata())
        case delete(path: AbsolutePath, metadata: DiffPathMetadata = DiffPathMetadata())
        case modify(path: AbsolutePath, metadata: DiffPathMetadata = DiffPathMetadata())
        case move(
            oldPath: AbsolutePath,
            path: AbsolutePath,
            metadata: DiffPathMetadata = DiffPathMetadata()
        )
        case copy(
            oldPath: AbsolutePath,
            path: AbsolutePath,
            metadata: DiffPathMetadata = DiffPathMetadata()
        )
        case other(operation: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case operation
            case path
            case oldPath
            case fileType
            case mimeType
            case _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let operation = try container.decode(String.self, forKey: .operation)
            let metadata = DiffPathMetadata(
                fileType: try container.decodeIfPresent(DiffFileType.self, forKey: .fileType),
                mimeType: try container.decodeIfPresent(MediaType.self, forKey: .mimeType),
                _meta: try container.decodeIfPresent(Meta.self, forKey: ._meta)
            )
            switch operation {
            case "add":
                self = .add(
                    path: try container.decode(AbsolutePath.self, forKey: .path),
                    metadata: metadata
                )
            case "delete":
                self = .delete(
                    path: try container.decode(AbsolutePath.self, forKey: .path),
                    metadata: metadata
                )
            case "modify":
                self = .modify(
                    path: try container.decode(AbsolutePath.self, forKey: .path),
                    metadata: metadata
                )
            case "move":
                self = .move(
                    oldPath: try container.decode(AbsolutePath.self, forKey: .oldPath),
                    path: try container.decode(AbsolutePath.self, forKey: .path),
                    metadata: metadata
                )
            case "copy":
                self = .copy(
                    oldPath: try container.decode(AbsolutePath.self, forKey: .oldPath),
                    path: try container.decode(AbsolutePath.self, forKey: .path),
                    metadata: metadata
                )
            default:
                self = .other(
                    operation: operation,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            if case .other(let operation, let fields) = self {
                try encodeV2RawObject(
                    fields,
                    discriminator: "operation",
                    value: operation,
                    to: encoder
                )
                return
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            let operation: String
            let path: AbsolutePath
            let oldPath: AbsolutePath?
            let metadata: DiffPathMetadata
            switch self {
            case .add(let value, let valueMetadata):
                operation = "add"
                path = value
                oldPath = nil
                metadata = valueMetadata
            case .delete(let value, let valueMetadata):
                operation = "delete"
                path = value
                oldPath = nil
                metadata = valueMetadata
            case .modify(let value, let valueMetadata):
                operation = "modify"
                path = value
                oldPath = nil
                metadata = valueMetadata
            case .move(let oldValue, let value, let valueMetadata):
                operation = "move"
                path = value
                oldPath = oldValue
                metadata = valueMetadata
            case .copy(let oldValue, let value, let valueMetadata):
                operation = "copy"
                path = value
                oldPath = oldValue
                metadata = valueMetadata
            case .other:
                return
            }
            try container.encode(operation, forKey: .operation)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(oldPath, forKey: .oldPath)
            try container.encodeIfPresent(metadata.fileType, forKey: .fileType)
            try container.encodeIfPresent(metadata.mimeType, forKey: .mimeType)
            try container.encodeIfPresent(metadata._meta, forKey: ._meta)
        }
    }

    public struct DiffPatch: Codable, Sendable {
        public let format: DiffPatchFormat
        public let text: String

        public init(format: DiffPatchFormat = "git_patch", text: String) {
            self.format = format
            self.text = text
        }
    }

    public struct Diff: Codable, Sendable {
        public let changes: [DiffChange]
        public let patch: DiffPatch?
        public let _meta: Meta?

        public init(changes: [DiffChange], patch: DiffPatch? = nil, _meta: Meta? = nil) {
            self.changes = changes
            self.patch = patch
            self._meta = _meta
        }
    }

    public struct Terminal: Codable, Sendable {
        public let terminalId: TerminalId
        public let _meta: Meta?

        public init(terminalId: TerminalId, _meta: Meta? = nil) {
            self.terminalId = terminalId
            self._meta = _meta
        }
    }

    public enum ToolCallContent: Codable, Sendable {
        case content(ContentBlock)
        case diff(Diff)
        case terminal(Terminal)
        case other(type: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case type
            case content
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "content":
                self = .content(try container.decode(ContentBlock.self, forKey: .content))
            case "diff":
                self = .diff(try Diff(from: decoder))
            case "terminal":
                self = .terminal(try Terminal(from: decoder))
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
            case .content(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("content", forKey: .type)
                try container.encode(value, forKey: .content)
            case .diff(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("diff", forKey: .type)
                try value.encode(to: encoder)
            case .terminal(let value):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("terminal", forKey: .type)
                try value.encode(to: encoder)
            }
        }
    }

    public struct ToolCallUpdate: Codable, Sendable {
        public let toolCallId: ToolCallId
        public let title: Patch<String>
        public let kind: Patch<ToolKind>
        public let status: Patch<ToolCallStatus>
        public let content: Patch<[ToolCallContent]>
        public let locations: Patch<[ToolCallLocation]>
        public let rawInput: Patch<AnyCodable>
        public let rawOutput: Patch<AnyCodable>
        public let meta: Patch<Meta>

        private enum CodingKeys: String, CodingKey {
            case toolCallId
            case title
            case kind
            case status
            case content
            case locations
            case rawInput
            case rawOutput
            case _meta
        }

        public init(
            toolCallId: ToolCallId,
            title: Patch<String> = .unchanged,
            kind: Patch<ToolKind> = .unchanged,
            status: Patch<ToolCallStatus> = .unchanged,
            content: Patch<[ToolCallContent]> = .unchanged,
            locations: Patch<[ToolCallLocation]> = .unchanged,
            rawInput: Patch<AnyCodable> = .unchanged,
            rawOutput: Patch<AnyCodable> = .unchanged,
            meta: Patch<Meta> = .unchanged
        ) {
            self.toolCallId = toolCallId
            self.title = title
            self.kind = kind
            self.status = status
            self.content = content
            self.locations = locations
            self.rawInput = rawInput
            self.rawOutput = rawOutput
            self.meta = meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            toolCallId = try container.decode(ToolCallId.self, forKey: .toolCallId)
            title = try decodeV2Patch(String.self, forKey: .title, from: container)
            kind = try decodeV2Patch(ToolKind.self, forKey: .kind, from: container)
            status = try decodeV2Patch(ToolCallStatus.self, forKey: .status, from: container)
            content = try decodeV2Patch([ToolCallContent].self, forKey: .content, from: container)
            locations = try decodeV2Patch(
                [ToolCallLocation].self,
                forKey: .locations,
                from: container
            )
            rawInput = try decodeV2Patch(AnyCodable.self, forKey: .rawInput, from: container)
            rawOutput = try decodeV2Patch(AnyCodable.self, forKey: .rawOutput, from: container)
            meta = try decodeV2Patch(Meta.self, forKey: ._meta, from: container)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(toolCallId, forKey: .toolCallId)
            try encodeV2Patch(title, forKey: .title, to: &container)
            try encodeV2Patch(kind, forKey: .kind, to: &container)
            try encodeV2Patch(status, forKey: .status, to: &container)
            try encodeV2Patch(content, forKey: .content, to: &container)
            try encodeV2Patch(locations, forKey: .locations, to: &container)
            try encodeV2Patch(rawInput, forKey: .rawInput, to: &container)
            try encodeV2Patch(rawOutput, forKey: .rawOutput, to: &container)
            try encodeV2Patch(meta, forKey: ._meta, to: &container)
        }
    }

    public struct ToolCallContentChunk: Codable, Sendable {
        public let toolCallId: ToolCallId
        public let content: ToolCallContent
        public let _meta: Meta?

        public init(toolCallId: ToolCallId, content: ToolCallContent, _meta: Meta? = nil) {
            self.toolCallId = toolCallId
            self.content = content
            self._meta = _meta
        }
    }
}

// MARK: - Terminals

extension ACPV2 {
    public struct TerminalOutput: Codable, Sendable {
        public let data: String
        public let _meta: Meta?

        public init(data: String, _meta: Meta? = nil) {
            self.data = data
            self._meta = _meta
        }
    }

    public struct TerminalExitStatus: Codable, Sendable {
        public let exitCode: UInt32?
        public let signal: String?
        public let _meta: Meta?

        public init(exitCode: UInt32? = nil, signal: String? = nil, _meta: Meta? = nil) {
            self.exitCode = exitCode
            self.signal = signal
            self._meta = _meta
        }
    }

    public struct TerminalUpdate: Codable, Sendable {
        public let terminalId: TerminalId
        public let command: Patch<String>
        public let cwd: Patch<AbsolutePath>
        public let output: Patch<TerminalOutput>
        public let exitStatus: Patch<TerminalExitStatus>
        public let meta: Patch<Meta>

        private enum CodingKeys: String, CodingKey {
            case terminalId
            case command
            case cwd
            case output
            case exitStatus
            case _meta
        }

        public init(
            terminalId: TerminalId,
            command: Patch<String> = .unchanged,
            cwd: Patch<AbsolutePath> = .unchanged,
            output: Patch<TerminalOutput> = .unchanged,
            exitStatus: Patch<TerminalExitStatus> = .unchanged,
            meta: Patch<Meta> = .unchanged
        ) {
            self.terminalId = terminalId
            self.command = command
            self.cwd = cwd
            self.output = output
            self.exitStatus = exitStatus
            self.meta = meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            terminalId = try container.decode(TerminalId.self, forKey: .terminalId)
            command = try decodeV2Patch(String.self, forKey: .command, from: container)
            cwd = try decodeV2Patch(AbsolutePath.self, forKey: .cwd, from: container)
            output = try decodeV2Patch(TerminalOutput.self, forKey: .output, from: container)
            exitStatus = try decodeV2Patch(
                TerminalExitStatus.self,
                forKey: .exitStatus,
                from: container
            )
            meta = try decodeV2Patch(Meta.self, forKey: ._meta, from: container)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(terminalId, forKey: .terminalId)
            try encodeV2Patch(command, forKey: .command, to: &container)
            try encodeV2Patch(cwd, forKey: .cwd, to: &container)
            try encodeV2Patch(output, forKey: .output, to: &container)
            try encodeV2Patch(exitStatus, forKey: .exitStatus, to: &container)
            try encodeV2Patch(meta, forKey: ._meta, to: &container)
        }
    }

    public struct TerminalOutputChunk: Codable, Sendable {
        public let terminalId: TerminalId
        public let data: String
        public let _meta: Meta?

        public init(terminalId: TerminalId, data: String, _meta: Meta? = nil) {
            self.terminalId = terminalId
            self.data = data
            self._meta = _meta
        }
    }
}

// MARK: - Plans, commands, metadata, and usage

extension ACPV2 {
    public struct PlanEntry: Codable, Sendable {
        public let content: String
        public let priority: PlanEntryPriority
        public let status: PlanEntryStatus
        public let _meta: Meta?

        public init(
            content: String,
            priority: PlanEntryPriority,
            status: PlanEntryStatus,
            _meta: Meta? = nil
        ) {
            self.content = content
            self.priority = priority
            self.status = status
            self._meta = _meta
        }
    }

    public enum PlanUpdateContent: Codable, Sendable {
        case items(planId: PlanId, entries: [PlanEntry], meta: Meta? = nil)
        case other(type: String, planId: PlanId, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case type
            case planId
            case entries
            case _meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            let planId = try container.decode(PlanId.self, forKey: .planId)
            if type == "items" {
                self = .items(
                    planId: planId,
                    entries: try container.decodeIfPresent([PlanEntry].self, forKey: .entries) ?? [],
                    meta: try container.decodeIfPresent(Meta.self, forKey: ._meta)
                )
            } else {
                self = .other(
                    type: type,
                    planId: planId,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .other(let type, let planId, let fields):
                var object = fields
                object["planId"] = AnyCodable(planId)
                try encodeV2RawObject(object, discriminator: "type", value: type, to: encoder)
            case .items(let planId, let entries, let meta):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("items", forKey: .type)
                try container.encode(planId, forKey: .planId)
                try container.encode(entries, forKey: .entries)
                try container.encodeIfPresent(meta, forKey: ._meta)
            }
        }
    }

    public struct PlanUpdate: Codable, Sendable {
        public let plan: PlanUpdateContent
        public let _meta: Meta?

        public init(plan: PlanUpdateContent, _meta: Meta? = nil) {
            self.plan = plan
            self._meta = _meta
        }
    }

    public enum AvailableCommandInput: Codable, Sendable {
        case text(hint: String)
        case other(type: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case type
            case hint
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            if type == "text" {
                self = .text(hint: try container.decode(String.self, forKey: .hint))
            } else {
                self = .other(
                    type: type,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let hint):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("text", forKey: .type)
                try container.encode(hint, forKey: .hint)
            case .other(let type, let fields):
                try encodeV2RawObject(fields, discriminator: "type", value: type, to: encoder)
            }
        }
    }

    public struct AvailableCommand: Codable, Sendable {
        public let name: String
        public let description: String
        public let input: AvailableCommandInput?
        public let _meta: Meta?

        public init(
            name: String,
            description: String,
            input: AvailableCommandInput? = nil,
            _meta: Meta? = nil
        ) {
            self.name = name
            self.description = description
            self.input = input
            self._meta = _meta
        }
    }

    public struct AvailableCommandsUpdate: Codable, Sendable {
        public let availableCommands: [AvailableCommand]
        public let _meta: Meta?

        public init(availableCommands: [AvailableCommand], _meta: Meta? = nil) {
            self.availableCommands = availableCommands
            self._meta = _meta
        }
    }

    public struct ConfigOptionUpdate: Codable, Sendable {
        public let configOptions: [SessionConfigOption]
        public let _meta: Meta?

        public init(configOptions: [SessionConfigOption], _meta: Meta? = nil) {
            self.configOptions = configOptions
            self._meta = _meta
        }
    }

    public struct SessionInfoUpdate: Codable, Sendable {
        public let title: Patch<String>
        public let updatedAt: Patch<String>
        public let meta: Patch<Meta>

        private enum CodingKeys: String, CodingKey {
            case title
            case updatedAt
            case _meta
        }

        public init(
            title: Patch<String> = .unchanged,
            updatedAt: Patch<String> = .unchanged,
            meta: Patch<Meta> = .unchanged
        ) {
            self.title = title
            self.updatedAt = updatedAt
            self.meta = meta
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try decodeV2Patch(String.self, forKey: .title, from: container)
            updatedAt = try decodeV2Patch(String.self, forKey: .updatedAt, from: container)
            meta = try decodeV2Patch(Meta.self, forKey: ._meta, from: container)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encodeV2Patch(title, forKey: .title, to: &container)
            try encodeV2Patch(updatedAt, forKey: .updatedAt, to: &container)
            try encodeV2Patch(meta, forKey: ._meta, to: &container)
        }
    }

    public struct Cost: Codable, Sendable {
        public let amount: Double
        public let currency: String
        public let _meta: Meta?

        public init(amount: Double, currency: String, _meta: Meta? = nil) {
            self.amount = amount
            self.currency = currency
            self._meta = _meta
        }
    }

    public struct UsageUpdate: Codable, Sendable {
        public let used: UInt64
        public let size: UInt64
        public let cost: Cost?
        public let _meta: Meta?

        public init(used: UInt64, size: UInt64, cost: Cost? = nil, _meta: Meta? = nil) {
            self.used = used
            self.size = size
            self.cost = cost
            self._meta = _meta
        }
    }
}

// MARK: - Session update notification

extension ACPV2 {
    public enum SessionUpdate: Codable, Sendable {
        case userMessageChunk(ContentChunk)
        case userMessage(MessageUpdate)
        case agentMessageChunk(ContentChunk)
        case agentMessage(MessageUpdate)
        case agentThoughtChunk(ContentChunk)
        case agentThought(MessageUpdate)
        case state(StateUpdate)
        case toolCallContentChunk(ToolCallContentChunk)
        case toolCall(ToolCallUpdate)
        case terminal(TerminalUpdate)
        case terminalOutputChunk(TerminalOutputChunk)
        case plan(PlanUpdate)
        case availableCommands(AvailableCommandsUpdate)
        case configOptions(ConfigOptionUpdate)
        case sessionInfo(SessionInfoUpdate)
        case usage(UsageUpdate)
        case other(type: String, fields: Meta)

        private enum CodingKeys: String, CodingKey {
            case sessionUpdate
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .sessionUpdate)
            switch type {
            case "user_message_chunk":
                self = .userMessageChunk(try ContentChunk(from: decoder))
            case "user_message":
                self = .userMessage(try MessageUpdate(from: decoder))
            case "agent_message_chunk":
                self = .agentMessageChunk(try ContentChunk(from: decoder))
            case "agent_message":
                self = .agentMessage(try MessageUpdate(from: decoder))
            case "agent_thought_chunk":
                self = .agentThoughtChunk(try ContentChunk(from: decoder))
            case "agent_thought":
                self = .agentThought(try MessageUpdate(from: decoder))
            case "state_update":
                self = .state(try StateUpdate(from: decoder))
            case "tool_call_content_chunk":
                self = .toolCallContentChunk(try ToolCallContentChunk(from: decoder))
            case "tool_call_update":
                self = .toolCall(try ToolCallUpdate(from: decoder))
            case "terminal_update":
                self = .terminal(try TerminalUpdate(from: decoder))
            case "terminal_output_chunk":
                self = .terminalOutputChunk(try TerminalOutputChunk(from: decoder))
            case "plan_update":
                self = .plan(try PlanUpdate(from: decoder))
            case "available_commands_update":
                self = .availableCommands(try AvailableCommandsUpdate(from: decoder))
            case "config_option_update":
                self = .configOptions(try ConfigOptionUpdate(from: decoder))
            case "session_info_update":
                self = .sessionInfo(try SessionInfoUpdate(from: decoder))
            case "usage_update":
                self = .usage(try UsageUpdate(from: decoder))
            default:
                self = .other(
                    type: type,
                    fields: try decoder.singleValueContainer().decode(Meta.self)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            if case .other(let type, let fields) = self {
                try encodeV2RawObject(
                    fields,
                    discriminator: "sessionUpdate",
                    value: type,
                    to: encoder
                )
                return
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .userMessageChunk(let value):
                try container.encode("user_message_chunk", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .userMessage(let value):
                try container.encode("user_message", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .agentMessageChunk(let value):
                try container.encode("agent_message_chunk", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .agentMessage(let value):
                try container.encode("agent_message", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .agentThoughtChunk(let value):
                try container.encode("agent_thought_chunk", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .agentThought(let value):
                try container.encode("agent_thought", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .state(let value):
                try container.encode("state_update", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .toolCallContentChunk(let value):
                try container.encode("tool_call_content_chunk", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .toolCall(let value):
                try container.encode("tool_call_update", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .terminal(let value):
                try container.encode("terminal_update", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .terminalOutputChunk(let value):
                try container.encode("terminal_output_chunk", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .plan(let value):
                try container.encode("plan_update", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .availableCommands(let value):
                try container.encode("available_commands_update", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .configOptions(let value):
                try container.encode("config_option_update", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .sessionInfo(let value):
                try container.encode("session_info_update", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .usage(let value):
                try container.encode("usage_update", forKey: .sessionUpdate)
                try value.encode(to: encoder)
            case .other:
                break
            }
        }
    }

    public struct SessionUpdateNotification: Codable, Sendable {
        public let sessionId: SessionId
        public let update: SessionUpdate
        public let _meta: Meta?

        public init(sessionId: SessionId, update: SessionUpdate, _meta: Meta? = nil) {
            self.sessionId = sessionId
            self.update = update
            self._meta = _meta
        }
    }
}
