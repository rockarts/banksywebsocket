//
//  File.swift
//  
//
//  Created by Steven Rockarts on 2024-07-13.
//

import Foundation


public enum WebSocketError: Error, CustomStringConvertible, Equatable {
    case invalidResponse
    case handshakeFailed
    case invalidAcceptKey
    case insufficientData
    case invalidOpcode
    case invalidState
    case unknownMessageType
    case protocolError(String)
    case unexpectedOpcode
    case notConnected
    case invalidUTF8
    case frameTooLarge
    case payloadLengthExceedsLimit
    case invalidCloseCode
    case controlFrameExceedsLimit
    case invalidCloseFramePayload
    case connectionClosed
    case controlFrameTooBig
    
    public var description: String {
        switch self {
        case .insufficientData: return "Insufficient data to parse WebSocket frame"
        case .invalidOpcode: return "Invalid WebSocket frame opcode"
        case .invalidUTF8: return "Invalid UTF-8 encoding in text frame"
        case .frameTooLarge: return "WebSocket frame exceeds maximum allowed size"
        case .invalidCloseCode: return "Invalid close frame status code"
        case .notConnected: return "WebSocket is not connected"
        case .invalidState: return "Invalid WebSocket state for operation"
        case .unknownMessageType: return "Unknown WebSocket message type received"
        case .unexpectedOpcode: return "Unexpected WebSocket frame opcode"
        case .invalidAcceptKey: return "Invalid Sec-WebSocket-Accept key in handshake response"
        case .protocolError(let message): return "WebSocket protocol error: \(message)"
        case .payloadLengthExceedsLimit: return "Payload length exceeds the maximum allowed limit"
        case .controlFrameExceedsLimit: return "Control frame exceeds the 125 bytes limit"
        case .invalidCloseFramePayload: return "Invalid close frame payload"
        case .connectionClosed: return "WebSocket connection is closed"
        case .invalidResponse: return "Invalid response"
        case .handshakeFailed: return "Handshake failed"
        case .controlFrameTooBig: return "Control frame exceeds the 125 bytes limit"
        }
    }
    
    public static func == (lhs: WebSocketError, rhs: WebSocketError) -> Bool {
            switch (lhs, rhs) {
            case (.invalidResponse, .invalidResponse),
                 (.handshakeFailed, .handshakeFailed),
                 (.invalidAcceptKey, .invalidAcceptKey),
                 (.insufficientData, .insufficientData),
                 (.invalidOpcode, .invalidOpcode),
                 (.invalidState, .invalidState),
                 (.unknownMessageType, .unknownMessageType),
                 (.unexpectedOpcode, .unexpectedOpcode),
                 (.notConnected, .notConnected),
                 (.invalidUTF8, .invalidUTF8),
                 (.frameTooLarge, .frameTooLarge),
                 (.payloadLengthExceedsLimit, .payloadLengthExceedsLimit),
                 (.invalidCloseCode, .invalidCloseCode),
                 (.controlFrameExceedsLimit, .controlFrameExceedsLimit),
                 (.invalidCloseFramePayload, .invalidCloseFramePayload),
                 (.connectionClosed, .connectionClosed),
                 (.controlFrameTooBig, .controlFrameTooBig):
                return true
            case (.protocolError(let lhsMessage), .protocolError(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
}
