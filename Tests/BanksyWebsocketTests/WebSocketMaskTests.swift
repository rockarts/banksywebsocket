//
//  WebSocketMaskTests.swift
//  
//
//  Created by Steven Rockarts on 2024-07-14.
//

import XCTest
@testable import BanksyWebsocket

class WebSocketMaskingTests: XCTestCase {

    func testMaskingAndUnmasking() {
        let payload = "Hello, WebSocket!"
        let maskingKey = Data([0xAA, 0xBB, 0xCC, 0xDD])
        
        let maskedData = WebSocketMask.applyMask(to: Data(payload.utf8), withKey: maskingKey)
        let unmaskedData = WebSocketMask.applyMask(to: maskedData, withKey: maskingKey)
        
        XCTAssertEqual(String(data: unmaskedData, encoding: .utf8), payload)
    }

    func testMaskingWithDifferentPayloadSizes() {
        let maskingKey = Data([0x12, 0x34, 0x56, 0x78])
        
        let payloads = [
            "A",
            "Hello",
            "This is a longer payload that exceeds the masking key length"
        ]
        
        for payload in payloads {
            let maskedData = WebSocketMask.applyMask(to: Data(payload.utf8), withKey: maskingKey)
            let unmaskedData = WebSocketMask.applyMask(to: maskedData, withKey: maskingKey)
            XCTAssertEqual(String(data: unmaskedData, encoding: .utf8), payload)
        }
    }

    func testMaskingChangesData() {
        let payload = "Hello, WebSocket!"
        let maskingKey = Data([0xAA, 0xBB, 0xCC, 0xDD])
        
        let maskedData = WebSocketMask.applyMask(to: Data(payload.utf8), withKey: maskingKey)
        
        XCTAssertNotEqual(maskedData, Data(payload.utf8))
    }
    
    func testMaskingWithDifferentKeys() {
        let payload = "Test payload"
        
        let maskingKeys = [
            Data([0xAA, 0xBB, 0xCC, 0xDD]),
            Data([0x11, 0x22, 0x33, 0x44]),
            Data([0xFF, 0x00, 0xFF, 0x00])
        ]
        
        for key in maskingKeys {
            let maskedData = WebSocketMask.applyMask(to: Data(payload.utf8), withKey: key)
            let unmaskedData = WebSocketMask.applyMask(to: maskedData, withKey: key)
            XCTAssertEqual(String(data: unmaskedData, encoding: .utf8), payload)
        }
    }
}
