//
//  ACPHTTPTests.swift
//  ACPHTTPTests
//
//  Tests for ACPHTTP module
//

import XCTest
@testable import ACPHTTP
@testable import ACP
@testable import ACPModel

final class ACPHTTPTests: XCTestCase {

    // MARK: - WebSocketTransport Tests

    func testWebSocketTransportCreation() async throws {
        let url = try XCTUnwrap(URL(string: "ws://localhost:8080"))
        let transport = WebSocketTransport(url: url)

        let isConnected = await transport.isConnected
        XCTAssertFalse(isConnected)
    }
}
