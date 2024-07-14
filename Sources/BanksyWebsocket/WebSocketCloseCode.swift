//
//  File.swift
//  
//
//  Created by Steven Rockarts on 2024-07-13.
//

import Foundation

public enum WebSocketCloseCode: UInt16 {
    case normal = 1000
    case goingAway = 1001
    case protocolError = 1002
    case unsupportedData = 1003
    case noStatusReceived = 1005
    case abnormalClosure = 1006
    case invalidFramePayloadData = 1007
    case policyViolation = 1008
    case messageTooBig = 1009
    case mandatoryExtension = 1010
    case internalServerError = 1011
    case tlsHandshake = 1015
    
    public static func isValid(_ code: UInt16) -> Bool {
        return (code >= 1000 && code <= 1003) ||
               (code >= 1007 && code <= 1011) ||
               (code >= 3000 && code <= 4999)
    }
}
