//
//  WebSocketFrame.swift
//
//
//  Created by Steven Rockarts on 2024-07-13.
//

import Foundation

// MARK: - WebSocket Frame

public struct WebSocketFrame {
    public let fin: Bool
    public let rsv1: Bool
    public let rsv2: Bool
    public let rsv3: Bool
    public let opcode: WebSocketOpcode
    public let masked: Bool
    public let payloadLength: UInt64
    public let maskingKey: Data?
    public let payloadData: Data
    
    public init(fin: Bool, rsv1: Bool = false, rsv2: Bool = false, rsv3: Bool = false,
                opcode: WebSocketOpcode, masked: Bool, payloadLength: UInt64,
                maskingKey: Data? = nil, payloadData: Data) {
        self.fin = fin
        self.rsv1 = rsv1
        self.rsv2 = rsv2
        self.rsv3 = rsv3
        self.opcode = opcode
        self.masked = masked
        self.payloadLength = payloadLength
        self.maskingKey = maskingKey
        self.payloadData = payloadData
    }
}

// MARK: - WebSocket Opcode

public enum WebSocketOpcode: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

// MARK: - WebSocket Frame Encoder/Decoder

public struct WebSocketFrameCodec {
    
    /// The maximum allowed size for a WebSocket frame.
    public let maxFrameSize: UInt64
    
    /// The maximum allowed size for a WebSocket control frame.
    public let maxControlFrameSize: UInt64
    
    /// Creates a new WebSocketFrameCodec with the specified frame size limits.
    ///
    /// - Parameters:
    ///   - maxFrameSize: The maximum allowed size for a WebSocket frame. Defaults to 100MB.
    ///   - maxControlFrameSize: The maximum allowed size for a WebSocket control frame. Defaults to 125 bytes.
    public init(maxFrameSize: UInt64 = 100 * 1024 * 1024, maxControlFrameSize: UInt64 = 125) {
        self.maxFrameSize = maxFrameSize
        self.maxControlFrameSize = maxControlFrameSize
    }
    
    /// Encodes a WebSocket frame into raw data.
    ///
    /// - Parameter frame: The WebSocket frame to encode.
    /// - Returns: The encoded frame as Data.
    /// - Throws: WebSocketError if encoding fails.
    public func encode(frame: WebSocketFrame) throws -> Data {
        
        guard frame.payloadLength <= maxFrameSize else {
            throw WebSocketError.frameTooLarge
        }
        
        if frame.opcode == .close || frame.opcode == .ping || frame.opcode == .pong {
            guard frame.payloadLength <= maxControlFrameSize else {
                throw WebSocketError.controlFrameTooBig
            }
        }
        
        if frame.opcode == .text {
            try validateUTF8(frame.payloadData)
        }
        
        var data = Data()
        
        // First byte: FIN, RSV1, RSV2, RSV3, opcode
        var byte: UInt8 = 0
        if frame.fin { byte |= 0b10000000 }
        if frame.rsv1 { byte |= 0b01000000 }
        if frame.rsv2 { byte |= 0b00100000 }
        if frame.rsv3 { byte |= 0b00010000 }
        byte |= frame.opcode.rawValue
        data.append(byte)
        
        // Second byte: Mask, Payload len
        var secondByte: UInt8 = frame.masked ? 0b10000000 : 0
        if frame.payloadLength <= 125 {
            secondByte |= UInt8(frame.payloadLength)
        } else if frame.payloadLength <= UInt16.max {
            secondByte |= 126
        } else {
            secondByte |= 127
        }
        data.append(secondByte)
        
        // Extended payload length
        if frame.payloadLength > 125 && frame.payloadLength <= UInt16.max {
            data.append(UInt16(frame.payloadLength).bigEndian.data)
        } else if frame.payloadLength > UInt16.max {
            data.append(UInt64(frame.payloadLength).bigEndian.data)
        }
        
        // Masking key
        if frame.masked {
            if let maskingKey = frame.maskingKey {
                data.append(maskingKey)
            } else {
                data.append(Data((0..<4).map { _ in UInt8.random(in: 0...255) }))
            }
        }
        
        // Payload data
        if frame.masked {
            data.append(applyMask(to: frame.payloadData, withKey: frame.maskingKey ?? data.suffix(4)))
        } else {
            data.append(frame.payloadData)
        }
        
        return data
    }
    
    /// Decodes raw data into a WebSocket frame.
    ///
    /// - Parameter data: The raw data to decode.
    /// - Returns: A tuple containing the decoded WebSocket frame and any remaining data.
    /// - Throws: WebSocketError if decoding fails.
    public func decode(data: Data) throws -> (WebSocketFrame, Data) {
        guard data.count >= 2 else { throw WebSocketError.insufficientData }
        
        var index = data.startIndex
        
        // First byte
        let firstByte = data[index]
        let fin = (firstByte & 0b10000000) != 0
        let rsv1 = (firstByte & 0b01000000) != 0
        let rsv2 = (firstByte & 0b00100000) != 0
        let rsv3 = (firstByte & 0b00010000) != 0
        guard let opcode = WebSocketOpcode(rawValue: firstByte & 0b00001111) else {
            throw WebSocketError.invalidOpcode
        }
        
        index = data.index(after: index)
        
        // Second byte
        let secondByte = data[index]
        let masked = (secondByte & 0b10000000) != 0
        var payloadLength = UInt64(secondByte & 0b01111111)
        
        index = data.index(after: index)
        
        // Extended payload length
        if payloadLength == 126 {
            guard data.count >= index + 2 else { throw WebSocketError.insufficientData }
            payloadLength = UInt64(data[index]) << 8 | UInt64(data[index + 1])
            index = data.index(index, offsetBy: 2)
        } else if payloadLength == 127 {
            guard data.count >= index + 8 else { throw WebSocketError.insufficientData }
            let bytes = [UInt8](data[index..<index+8])
            payloadLength = bytesToUInt64(bytes)
            index = data.index(index, offsetBy: 8)
            
            print("Decoded payload length bytes: \(bytes.map { String(format: "%02X", $0) }.joined())")
        }
        
        debugPrint("Decoded payload length: \(payloadLength)")
        debugPrint("Max frame size: \(maxFrameSize)")
        
        if (opcode == .close || opcode == .ping || opcode == .pong) && payloadLength > maxControlFrameSize {
            throw WebSocketError.controlFrameTooBig
        }
        
        guard payloadLength <= maxFrameSize else {
            throw WebSocketError.frameTooLarge
        }
        
        // Masking key
        var maskingKey: Data?
        if masked {
            guard data.count >= index + 4 else { throw WebSocketError.insufficientData }
            maskingKey = data[index..<data.index(index, offsetBy: 4)]
            index = data.index(index, offsetBy: 4)
        }
        
        // Payload data
        guard data.count >= index + Int(payloadLength) else { throw WebSocketError.insufficientData }
        let payloadData = data[index..<data.index(index, offsetBy: Int(payloadLength))]
        index = data.index(index, offsetBy: Int(payloadLength))
        
        let unmaskedPayloadData: Data
        if masked, let key = maskingKey {
            unmaskedPayloadData = applyMask(to: payloadData, withKey: key)
        } else {
            unmaskedPayloadData = payloadData
        }
        
        // UTF-8 validation for text frames
        if opcode == .text {
            try validateUTF8(payloadData)
        }
        
        let frame = WebSocketFrame(fin: fin, rsv1: rsv1, rsv2: rsv2, rsv3: rsv3,
                                   opcode: opcode, masked: masked, payloadLength: payloadLength,
                                   maskingKey: maskingKey, payloadData: payloadData)
        
        return (frame, data[index...])
    }
    
    private func bytesToUInt64(_ bytes: [UInt8]) -> UInt64 {
        assert(bytes.count == 8, "Expected 8 bytes for UInt64")
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
    
    private func applyMask(to data: Data, withKey key: Data) -> Data {
        return WebSocketMask.applyMask(to: data, withKey: key)
    }
    
    func validateUTF8(_ data: Data) throws {
        guard String(data: data, encoding: .utf8) != nil else {
            throw WebSocketError.invalidUTF8
        }
    }
}

// MARK: - Helpers

extension FixedWidthInteger {
    var data: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
