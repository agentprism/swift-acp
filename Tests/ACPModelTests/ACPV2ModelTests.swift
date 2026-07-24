import XCTest
@testable import ACPModel

final class ACPV2ModelTests: XCTestCase {
    func testInitializeUsesV2WireShape() throws {
        let request = ACPV2.InitializeRequest(
            info: ACPV2.Implementation(name: "test-client", version: "1.0"),
            capabilities: ACPV2.ClientCapabilities()
        )

        let object = try jsonObject(request)

        XCTAssertEqual(object["protocolVersion"] as? Int, 2)
        XCTAssertNotNil(object["info"])
        XCTAssertNotNil(object["capabilities"])
        XCTAssertNil(object["clientInfo"])
        XCTAssertNil(object["clientCapabilities"])
    }

    func testMinimalValidV2PayloadsDefaultOmittedCollections() throws {
        let initialize = try JSONDecoder().decode(
            ACPV2.InitializeResponse.self,
            from: Data(
                #"{"protocolVersion":2,"info":{"name":"agent","version":"1.0"}}"#.utf8
            )
        )
        XCTAssertTrue(initialize.authMethods.isEmpty)

        let session = try JSONDecoder().decode(
            ACPV2.NewSessionResponse.self,
            from: Data(#"{"sessionId":"session-1"}"#.utf8)
        )
        XCTAssertTrue(session.configOptions.isEmpty)

        let resume = try JSONDecoder().decode(
            ACPV2.ResumeSessionRequest.self,
            from: Data(#"{"sessionId":"session-1","cwd":"/tmp"}"#.utf8)
        )
        XCTAssertTrue(resume.additionalDirectories.isEmpty)
        XCTAssertTrue(resume.mcpServers.isEmpty)

        let server = try JSONDecoder().decode(
            ACPV2.MCPServer.self,
            from: Data(#"{"type":"stdio","name":"server","command":"/bin/server"}"#.utf8)
        )
        guard case .stdio(let stdio) = server else {
            return XCTFail("Expected stdio MCP server")
        }
        XCTAssertTrue(stdio.args.isEmpty)
        XCTAssertTrue(stdio.env.isEmpty)
    }

    func testUnknownAuthMethodFieldsRoundTrip() throws {
        let data = Data(
            #"{"type":"future_auth","methodId":"future","name":"Future","extensionValue":42}"#.utf8
        )
        let method = try JSONDecoder().decode(ACPV2.AuthMethod.self, from: data)

        XCTAssertEqual(method.type, "future_auth")
        XCTAssertEqual(method.additionalFields["extensionValue"]?.value as? Int, 42)
        XCTAssertEqual(
            try jsonObject(method)["extensionValue"] as? Int,
            42
        )
    }

    func testPatchDistinguishesOmittedNullAndValue() throws {
        let update = ACPV2.MessageUpdate(
            messageId: "message-1",
            content: .clear,
            meta: .value(["source": AnyCodable("test")])
        )

        let object = try jsonObject(update)

        XCTAssertTrue(object["content"] is NSNull)
        XCTAssertEqual(
            (object["_meta"] as? [String: Any])?["source"] as? String,
            "test"
        )

        let decoded = try JSONDecoder().decode(
            ACPV2.MessageUpdate.self,
            from: Data(#"{"messageId":"message-2"}"#.utf8)
        )
        if case .unchanged = decoded.content {
            // Expected.
        } else {
            XCTFail("Omitted content must decode as unchanged")
        }
    }

    func testStateAndUnknownUpdatesAreFutureCompatible() throws {
        let idle = try JSONDecoder().decode(
            ACPV2.SessionUpdate.self,
            from: Data(
                #"{"sessionUpdate":"state_update","state":"idle","stopReason":"future_reason"}"#.utf8
            )
        )
        guard case .state(.idle(let reason, _)) = idle else {
            return XCTFail("Expected idle state update")
        }
        XCTAssertEqual(reason?.rawValue, "future_reason")

        let unknownJSON = Data(
            #"{"sessionUpdate":"future_update","newField":42}"#.utf8
        )
        let unknown = try JSONDecoder().decode(
            ACPV2.SessionUpdate.self,
            from: unknownJSON
        )
        guard case .other(let type, let fields) = unknown else {
            return XCTFail("Expected preserved unknown update")
        }
        XCTAssertEqual(type, "future_update")
        XCTAssertEqual(fields["newField"]?.value as? Int, 42)

        let roundTrip = try jsonObject(unknown)
        XCTAssertEqual(roundTrip["sessionUpdate"] as? String, "future_update")
        XCTAssertEqual(roundTrip["newField"] as? Int, 42)
    }

    func testElicitationModesAndActionsUseFlattenedWireShape() throws {
        let request = ACPV2.CreateElicitationRequest(
            mode: .form(
                scope: .session(sessionId: "session-1", toolCallId: "tool-1"),
                requestedSchema: ACPV2.ElicitationSchema(
                    properties: [
                        "name": [
                            "type": AnyCodable("string"),
                            "title": AnyCodable("Name"),
                        ],
                    ],
                    required: ["name"]
                )
            ),
            message: "Your name?"
        )

        let object = try jsonObject(request)

        XCTAssertEqual(object["mode"] as? String, "form")
        XCTAssertEqual(object["sessionId"] as? String, "session-1")
        XCTAssertEqual(object["toolCallId"] as? String, "tool-1")
        XCTAssertEqual(object["message"] as? String, "Your name?")
        XCTAssertNotNil(object["requestedSchema"])

        let response = try JSONDecoder().decode(
            ACPV2.CreateElicitationResponse.self,
            from: Data(
                #"{"action":"accept","content":{"name":"Wiedy","count":2}}"#.utf8
            )
        )
        guard case .accept(let content) = response.action else {
            return XCTFail("Expected accept action")
        }
        guard case .string("Wiedy")? = content?["name"],
              case .integer(2)? = content?["count"] else {
            return XCTFail("Expected typed elicitation values")
        }
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
