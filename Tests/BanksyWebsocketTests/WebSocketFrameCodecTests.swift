import XCTest
@testable import BanksyWebsocket

class WebSocketFrameCodecTests: XCTestCase {
    let codec = WebSocketFrameCodec()

    func testEncodeSimpleTextFrame() throws {
        let payload = "Hello, WebSocket!"
        let frame = WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: true,
            payloadLength: UInt64(payload.utf8.count),
            payloadData: Data(payload.utf8)
        )
        
        let encodedData = try codec.encode(frame: frame)
        
        XCTAssertEqual(encodedData[0], 0b10000001) // FIN + Text opcode
        XCTAssertEqual(encodedData[1] & 0b10000000, 0b10000000) // MASK bit set
        XCTAssertEqual(encodedData[1] & 0b01111111, 17) // Payload length
        XCTAssertEqual(encodedData.count, 6 + payload.utf8.count) // 2 header + 4 mask + payload
    }

    func testEncodeUnmaskedBinaryFrame() throws {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let frame = WebSocketFrame(
            fin: true,
            opcode: .binary,
            masked: false,
            payloadLength: UInt64(payload.count),
            payloadData: payload
        )
        
        let encodedData = try codec.encode(frame: frame)
        
        XCTAssertEqual(encodedData[0], 0b10000010) // FIN + Binary opcode
        XCTAssertEqual(encodedData[1], 4) // Unmasked + Payload length
        XCTAssertEqual(encodedData.count, 2 + payload.count) // 2 header + payload
        XCTAssertEqual(encodedData.suffix(4), payload)
    }

    func testEncodeLargeFrame() throws {
        let payload = Data(repeating: 0x42, count: 65536) // 64KB
        let frame = WebSocketFrame(
            fin: true,
            opcode: .binary,
            masked: false,
            payloadLength: UInt64(payload.count),
            payloadData: payload
        )
        
        let encodedData = try codec.encode(frame: frame)
        
        XCTAssertEqual(encodedData[0], 0b10000010) // FIN + Binary opcode
        XCTAssertEqual(encodedData[1], 127) // Payload length indicator for 64-bit length
        XCTAssertEqual(encodedData[2...9], UInt64(65536).bigEndian.data)
        XCTAssertEqual(encodedData.count, 10 + payload.count) // 2 header + 8 extended length + payload
    }

    func testDecodeMaskedFrame() throws {
        let codec = WebSocketFrameCodec()
        let payload = "Hello, WebSocket!"
        let maskingKey = Data([0xAA, 0xBB, 0xCC, 0xDD])
        var maskedPayload = Data(payload.utf8)
        for i in 0..<maskedPayload.count {
            maskedPayload[i] ^= maskingKey[i % 4]
        }
        let encodedData = Data([0x81, 0x91]) + maskingKey + maskedPayload

        let (decodedFrame, remainingData) = try codec.decode(data: encodedData)
        
        XCTAssertTrue(decodedFrame.masked)
        XCTAssertEqual(decodedFrame.opcode, .text)
        XCTAssertEqual(String(data: decodedFrame.payloadData, encoding: .utf8), payload)
        XCTAssertTrue(remainingData.isEmpty)
    }

    func testDecodeUnmaskedBinaryFrame() throws {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let encodedData = Data([0x82, 0x04]) + payload
        
        let (decodedFrame, remainingData) = try codec.decode(data: encodedData)
        
        XCTAssertTrue(decodedFrame.fin)
        XCTAssertEqual(decodedFrame.opcode, .binary)
        XCTAssertFalse(decodedFrame.masked)
        XCTAssertEqual(decodedFrame.payloadLength, UInt64(payload.count))
        XCTAssertEqual(decodedFrame.payloadData, payload)
        XCTAssertTrue(remainingData.isEmpty)
    }

    func testDecodeLargeFrame() throws {
        let codec = WebSocketFrameCodec(maxFrameSize: 100000)
        let payload = Data(repeating: 0x42, count: 65536) // 64KB
        let payloadLength: UInt64 = 65536
        let payloadLengthBytes = withUnsafeBytes(of: payloadLength.bigEndian) { Data($0) }
        let encodedData = Data([0x82, 127]) + payloadLengthBytes + payload
        
        print("Encoded data size: \(encodedData.count)")
        print("Payload size: \(payload.count)")
        print("Max frame size: \(codec.maxFrameSize)")
        print("Payload length bytes: \(payloadLengthBytes.map { String(format: "%02X", $0) }.joined())")
        
        let (decodedFrame, remainingData) = try codec.decode(data: encodedData)
        
        XCTAssertTrue(decodedFrame.fin)
        XCTAssertEqual(decodedFrame.opcode, .binary)
        XCTAssertFalse(decodedFrame.masked)
        XCTAssertEqual(decodedFrame.payloadLength, UInt64(payload.count))
        XCTAssertEqual(decodedFrame.payloadData, payload)
        XCTAssertTrue(remainingData.isEmpty)
    }

    func testDecodeInsufficientData() {
        let incompleteData = Data([0x81, 0x11]) // Header for a masked text frame, but no mask or payload
        
        XCTAssertThrowsError(try codec.decode(data: incompleteData)) { error in
            XCTAssertEqual(error as? WebSocketError, .insufficientData)
        }
    }

    func testDecodeInvalidOpcode() {
        let invalidData = Data([0x8F, 0x00]) // Invalid opcode 0xF
        
        XCTAssertThrowsError(try codec.decode(data: invalidData)) { error in
            XCTAssertEqual(error as? WebSocketError, .invalidOpcode)
        }
    }

    func testRoundTrip() throws {
        let originalFrame = WebSocketFrame(
            fin: true,
            rsv1: false,
            rsv2: true,
            rsv3: false,
            opcode: .text,
            masked: true,
            payloadLength: 5,
            maskingKey: Data([0xAA, 0xBB, 0xCC, 0xDD]),
            payloadData: Data("Hello".utf8)
        )
        
        let encodedData = try codec.encode(frame: originalFrame)
        
        let (decodedFrame, remainingData) = try codec.decode(data: encodedData)
        
        XCTAssertEqual(decodedFrame.fin, originalFrame.fin)
        XCTAssertEqual(decodedFrame.rsv1, originalFrame.rsv1)
        XCTAssertEqual(decodedFrame.rsv2, originalFrame.rsv2)
        XCTAssertEqual(decodedFrame.rsv3, originalFrame.rsv3)
        XCTAssertEqual(decodedFrame.opcode, originalFrame.opcode)
        XCTAssertEqual(decodedFrame.masked, originalFrame.masked)
        XCTAssertEqual(decodedFrame.payloadLength, originalFrame.payloadLength)
        XCTAssertEqual(decodedFrame.payloadData, originalFrame.payloadData)
        XCTAssertTrue(remainingData.isEmpty)
    }
}
