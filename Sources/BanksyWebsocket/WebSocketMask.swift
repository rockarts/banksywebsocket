//
//  WebSocketMask.swift
//  
//
//  Created by Steven Rockarts on 2024-07-14.
//

import Foundation

import Foundation

public struct WebSocketMask {
    public static func applyMask(to data: Data, withKey key: Data) -> Data {
        precondition(key.count == 4, "Masking key must be 4 bytes long")
        
        let keyArray = [UInt8](key)
        return Data(data.enumerated().map { (index, byte) in
            return byte ^ keyArray[index % 4]
        })
    }
}
