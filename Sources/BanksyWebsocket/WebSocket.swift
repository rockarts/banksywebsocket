//
//  WebSocket.swift
//
//
//  Created by Steven Rockarts on 2024-07-13.
//

import Foundation
import Combine
import CryptoKit

@available(iOS 13.0, macOS 10.15, *)
public actor WebSocket {
    private let url: URL
    public nonisolated let urlSession: URLSession
    private var task: URLSessionWebSocketTask!
    
    private var isClosing = false
    
    private var lastMessageReceivedTime: Date = Date()
    private let timeoutInterval: TimeInterval = 60
    
    public enum State {
        case disconnected, connecting, connected
    }
    
    @Published public private(set) var state: State = .disconnected

    public typealias WebSocketMessage = URLSessionWebSocketTask.Message

    private let messageSequence: AsyncThrowingStream<WebSocketMessage, Error>
    private let messageContinuation: AsyncThrowingStream<WebSocketMessage, Error>.Continuation
    
    public var messages: AsyncThrowingStream<WebSocketMessage, Error> {
        return messageSequence
    }
    
    private enum FragmentationState {
        case notFragmented
        case fragmenting(opcode: WebSocketOpcode, data: Data)
    }
    
    private var fragmentationState: FragmentationState = .notFragmented
    
    private let codec: WebSocketFrameCodec
    
    public init(url: URL, maxFrameSize: UInt64 = 100 * 1024 * 1024, maxControlFrameSize: UInt64 = 125) {
        self.url = url
        let configuration = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: configuration)
        self.codec = WebSocketFrameCodec(maxFrameSize: maxFrameSize, maxControlFrameSize: maxControlFrameSize)
        (self.messageSequence, self.messageContinuation) = AsyncThrowingStream.makeStream()
    }
    
    
    public func connect() async throws {
        guard state == .disconnected else {
            throw WebSocketError.invalidState
        }
        
        state = .connecting
        task = urlSession.webSocketTask(with: url)
        task.resume()
        
        do {
            try await performHandshake()
            state = .connected
            startPingTimer()
            receiveMessage()
        } catch {
            state = .disconnected
            throw error
        }
    }
    
    private func performHandshake() async throws {
        let keyBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let key = Data(keyBytes).base64EncodedString()
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue(key, forHTTPHeaderField: "Sec-WebSocket-Key")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebSocketError.invalidResponse
        }
        
        guard httpResponse.statusCode == 101,
              httpResponse.value(forHTTPHeaderField: "Upgrade")?.lowercased() == "websocket",
              httpResponse.value(forHTTPHeaderField: "Connection")?.lowercased() == "upgrade" else {
            throw WebSocketError.handshakeFailed
        }
        
        let acceptKey = httpResponse.value(forHTTPHeaderField: "Sec-WebSocket-Accept")
        let expectedAcceptKey = calculateAcceptKey(key: key)
        
        guard acceptKey == expectedAcceptKey else {
            throw WebSocketError.invalidAcceptKey
        }
        
        print("WebSocket handshake successful")
    }
    
    private func calculateAcceptKey(key: String) -> String {
        let concatenatedKey = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let sha1 = Insecure.SHA1.hash(data: concatenatedKey.data(using: .utf8)!)
        return Data(sha1).base64EncodedString()
    }
    
    public func disconnect() async {
        guard state == .connected else { return }
        
        isClosing = true
        state = .disconnected
        
        do {
            try await close(code: WebSocketCloseCode.normal.rawValue, reason: "Normal closure")
        } catch {
            handleError(error)
        }
        
        messageContinuation.finish()
    }
    
    private func receiveMessage() {
        guard state == .connected else { return }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            Task {
                await self.handleReceiveResult(result)
            }
        }
    }
    
    private func handleReceiveResult(_ result: Result<URLSessionWebSocketTask.Message, Error>) async {
        messageContinuation.yield(with: result)
        
        switch result {
        case .success:
            receiveMessage() // Continue receiving messages
        case .failure(let error):
            handleError(error)
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        lastMessageReceivedTime = Date()
        
        switch message {
        case .data(let data):
            await handleReceivedData(data)
        case .string(let text):
            messageContinuation.yield(with: .success(.string(text)))
        @unknown default:
            messageContinuation.finish(throwing: WebSocketError.unknownMessageType)
        }
    }
    
    private func handleReceivedData(_ data: Data) async {
        do {
            var remainingData = data
            while !remainingData.isEmpty {
                do {
                    let (frame, leftover) = try codec.decode(data: remainingData)
                    try await handleFrame(frame)
                    remainingData = leftover
                } catch let error as WebSocketError {
                    switch error {
                    case .invalidUTF8:
                        try await close(code: WebSocketCloseCode.invalidFramePayloadData.rawValue, reason: error.description)
                    case .frameTooLarge:
                        try await close(code: WebSocketCloseCode.messageTooBig.rawValue, reason: error.description)
                    case .protocolError(let message):
                        try await close(code: WebSocketCloseCode.protocolError.rawValue, reason: message)
                    default:
                        try await close(code: WebSocketCloseCode.protocolError.rawValue, reason: error.description)
                    }
                    break
                }
            }
        } catch {
            handleError(error)
        }
    }
    
    private func handleFrame(_ frame: WebSocketFrame) async throws {
        switch frame.opcode {
        case .continuation:
            try await handleContinuation(frame)
        case .text, .binary:
            if case .fragmenting = fragmentationState {
                throw WebSocketError.protocolError("Received new data frame while still fragmenting")
            }
            if frame.fin {
                await handleCompleteMessage(opcode: frame.opcode, data: frame.payloadData)
            } else {
                fragmentationState = .fragmenting(opcode: frame.opcode, data: frame.payloadData)
            }
        case .close:
            await handleCloseFrame(frame)
        case .ping:
            await sendPong(frame.payloadData)
        case .pong:
            await handlePong(frame.payloadData)
        }
    }
    
    private func handleContinuation(_ frame: WebSocketFrame) async throws {
        switch fragmentationState {
        case .notFragmented:
            throw WebSocketError.protocolError("Received unexpected continuation frame")
        case .fragmenting(let opcode, var data):
            data.append(frame.payloadData)
            if frame.fin {
                await handleCompleteMessage(opcode: opcode, data: data)
                fragmentationState = .notFragmented
            } else {
                fragmentationState = .fragmenting(opcode: opcode, data: data)
            }
        }
    }
    
    private func handleCompleteMessage(opcode: WebSocketOpcode, data: Data) async {
        switch opcode {
        case .text:
            if let text = String(data: data, encoding: .utf8) {
                messageContinuation.yield(with: .success(.string(text)))
            } else {
                messageContinuation.yield(with: .failure(WebSocketError.invalidUTF8))
            }
        case .binary:
            messageContinuation.yield(with: .success(.data(data)))
        default:
            messageContinuation.yield(with: .failure(WebSocketError.unexpectedOpcode))
        }
    }
    
    private func handleCloseFrame(_ frame: WebSocketFrame) async {
        if !isClosing {
            isClosing = true
            
            var statusCode: WebSocketCloseCode = .normal
            var reason: String?
            
            if frame.payloadData.count == 1 {
                // Invalid close frame
                do {
                    try await close(code: WebSocketCloseCode.protocolError.rawValue, reason: "Invalid close frame payload length")
                } catch {
                    handleError(error)
                }
                return
            }
            
            if frame.payloadData.count >= 2 {
                let receivedCode = frame.payloadData.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
                statusCode = WebSocketCloseCode(rawValue: receivedCode) ?? .protocolError
                
                if frame.payloadData.count > 2 {
                    reason = String(data: frame.payloadData.dropFirst(2), encoding: .utf8)
                }
            }
            
            print("Received close frame with status code: \(statusCode.rawValue), reason: \(reason ?? "No reason provided")")
            
            // Send a close frame in response
            do {
                try await close(code: statusCode.rawValue, reason: "Responding to close frame")
                state = .disconnected
            } catch {
                handleError(error)
            }
        }
        
        task.cancel(with: .goingAway, reason: nil)
    }
    
    private func sendPong(_ payload: Data) async {
        let pongFrame = WebSocketFrame(fin: true, opcode: .pong, masked: true, payloadLength: UInt64(payload.count), payloadData: payload)
        do {
            let encodedPong = try codec.encode(frame: pongFrame)
            
            try await task.send(.data(encodedPong))
        } catch {
            handleError(error)
        }
    }
    
    private func handlePong(_ payload: Data) async {
        lastMessageReceivedTime = Date()
        // Reset ping timer or update last pong received time
        print("Received pong with payload: \(payload.count) bytes")
    }
    
    private func handleError(_ error: Error) {
        messageContinuation.finish(throwing: error)
        if state != .disconnected {
            Task {
                await disconnect()
            }
        }
    }
    
    private func startPingTimer() {
        Task {
            while state == .connected {
                try? await Task.sleep(nanoseconds: UInt64(30 * 1_000_000_000)) // 30 seconds
                await checkConnectionAndSendPing()
            }
        }
    }
    
    private func checkConnectionAndSendPing() async {
        let currentTime = Date()
        if currentTime.timeIntervalSince(lastMessageReceivedTime) > timeoutInterval {
            await handleTimeout()
        } else {
            do {
                try await sendPing()
            } catch {
                handleError(error)
            }
        }
    }
    
    private func sendPing() async throws {
        let pingFrame = WebSocketFrame(fin: true, opcode: .ping, masked: true, payloadLength: 0, payloadData: Data())
        let encodedPing = try codec.encode(frame: pingFrame)
        try await task.send(.data(encodedPing))
    }
    
    private func handleTimeout() async {
        do {
            try await close(code: WebSocketCloseCode.goingAway.rawValue, reason: "Connection timed out")
        } catch {
            handleError(error)
        }
    }
        
    public func send(text: String) async throws {
        guard state == .connected else {
            throw WebSocketError.notConnected
        }
        
        let data = Data(text.utf8)
        let frame = WebSocketFrame(fin: true, opcode: .text, masked: true, payloadLength: UInt64(data.count), payloadData: data)
        let encodedFrame = try codec.encode(frame: frame)
        try await task.send(.data(encodedFrame))
    }
    
    public func send(data: Data) async throws {
        guard state == .connected else {
            throw WebSocketError.notConnected
        }
        
        let frame = WebSocketFrame(fin: true, opcode: .binary, masked: true, payloadLength: UInt64(data.count), payloadData: data)
        let encodedFrame = try codec.encode(frame: frame)
        try await task.send(.data(encodedFrame))
    }
    
    private func close(code: UInt16 = WebSocketCloseCode.normal.rawValue, reason: String? = nil) async throws {
        guard WebSocketCloseCode.isValid(code) else {
            print("Invalid close code: \(code). Using normal closure.")
            return try await close(code: WebSocketCloseCode.normal.rawValue, reason: reason)
        }
        
        var payload = code.bigEndian.data
        if let reason = reason {
            guard let reasonData = reason.data(using: .utf8) else {
                print("Invalid UTF-8 in close reason. Sending without reason.")
                return try await close(code: code, reason: nil)
            }
            
            // Check if the total payload (2 bytes for code + reason) exceeds 125 bytes
            if (payload.count + reasonData.count) <= codec.maxControlFrameSize {
                payload.append(reasonData)
            } else {
                print("Close frame payload too large. Truncating reason.")
                let maxReasonLength = Int(codec.maxControlFrameSize) - payload.count
                payload.append(reasonData.prefix(maxReasonLength))
            }
        }
        
        let closeFrame = WebSocketFrame(fin: true, opcode: .close, masked: true, payloadLength: UInt64(payload.count), payloadData: payload)
        let encodedClose = try codec.encode(frame: closeFrame)
        try await task.send(.data(encodedClose))
        isClosing = true
        state = .disconnected
        task.cancel(with: .goingAway, reason: nil)
    }
}
