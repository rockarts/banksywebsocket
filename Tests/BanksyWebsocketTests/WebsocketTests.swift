////
////  File.swift
////  
////
////  Created by Steven Rockarts on 2024-07-13.
//

import Foundation
import XCTest

@testable import BanksyWebsocket

class WebSocketTests: XCTestCase {
    var webSocket: WebSocket!
    let timeout: TimeInterval = 5.0

    override func setUpWithError() throws {
        try super.setUpWithError()
        let url = URL(string: "wss://echo.websocket.org")!
        webSocket = WebSocket(url: url)
    }

    override func tearDownWithError() throws {
        webSocket = nil
        try super.tearDownWithError()
    }

    func testConnect() async throws {
        try await webSocket.connect()
        let state = await webSocket.state
        XCTAssertEqual(state, .connected)
    }

    func testSendAndReceiveTextMessage() async throws {
        try await webSocket.connect()
        
        let testMessage = "Hello, WebSocket!"
        try await webSocket.send(text: testMessage)
        
        let expectation = XCTestExpectation(description: "Receive echoed message")
        
        Task {
            for try await message in await webSocket.messages {
                if case .string(let receivedText) = message {
                    XCTAssertEqual(receivedText, testMessage)
                    expectation.fulfill()
                    break
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: timeout)
    }

    func testSendAndReceiveBinaryMessage() async throws {
        try await webSocket.connect()
        
        let testData = "Binary data".data(using: .utf8)!
        try await webSocket.send(data: testData)
        
        let expectation = XCTestExpectation(description: "Receive echoed binary data")
        
        Task {
            for try await message in await webSocket.messages {
                if case .data(let receivedData) = message {
                    XCTAssertEqual(receivedData, testData)
                    expectation.fulfill()
                    break
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: timeout)
    }

    func testDisconnect() async throws {
        try await webSocket.connect()
        var state = await webSocket.state
        XCTAssertEqual(state, .connected)
        
        await webSocket.disconnect()
        state = await webSocket.state
        XCTAssertEqual(state, .disconnected)
    }

    func testReconnect() async throws {
        try await webSocket.connect()
        var state = await webSocket.state
        XCTAssertEqual(state, .connected)
        
        await webSocket.disconnect()
        state = await webSocket.state
        XCTAssertEqual(state, .disconnected)
        
        try await webSocket.connect()
        state = await webSocket.state
        XCTAssertEqual(state, .connected)
    }

    func testPingPong() async throws {
        try await webSocket.connect()
        
        // Wait for a bit to allow for a ping to be sent and a pong to be received
        try await Task.sleep(nanoseconds: 35_000_000_000)  // 35 seconds
        
        // Check if the connection is still alive
        let state = await webSocket.state
        XCTAssertEqual(state, .connected)
    }
}
