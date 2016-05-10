//
//  Crypto.swift
//  AirMuler
//
//  Created by Ankush Gupta on 3/29/16.
//  Copyright © 2016 AirMuler. All rights reserved.
//

import Foundation
import Sodium
import SwiftyJSON

public typealias PublicKey = Box.PublicKey
public typealias SecretKey = Box.SecretKey
public typealias KeyPair = Box.KeyPair

extension KeyPair {
    init(publicKey: PublicKey, secretKey: SecretKey) {
        self.publicKey = publicKey
        self.secretKey = secretKey
    }
}

enum MessageType: Int {
    case Content
    case Ack
}
    
struct MessageContainer {
	let messageType: MessageType
	let ackMessage: AckMessage?
	let contentMessage: ContentMessage?
    
    func toJSON() throws -> NSData? {
        var props: JSON = [:]
        if messageType == MessageType.Ack {
            props = try ["messageType": messageType.rawValue, "ackMessage": ackMessage!.toJSON()!.base64EncodedStringWithOptions([])]
        } else if messageType == MessageType.Content {
            props = try ["messageType": messageType.rawValue, "contentMessage": contentMessage!.toJSON()!.base64EncodedStringWithOptions([])]
        }
        return try props.rawData()
    }
}

struct ContentMessage {
	let uuid: PublicKey
	let uuidEnc: NSData
	let dispatchEnc: NSData
	let dispatchKeyEnc: NSData
    
    func toJSON() throws -> NSData? {
        let props: JSON = ["uuid": uuid.base64EncodedStringWithOptions([]), "uuidEnc": uuidEnc.base64EncodedStringWithOptions([]), "dispatchEnc": dispatchEnc.base64EncodedStringWithOptions([]), "dispatchKeyEnc": dispatchKeyEnc.base64EncodedStringWithOptions([])]
        return try props.rawData()
    }
}

struct AckMessage {
	let uuid: PublicKey;
	let ackKey: NSData;
    
    func toJSON() throws -> NSData? {
        let props: JSON = ["uuid": uuid.base64EncodedStringWithOptions([]), "ackKey": ackKey.base64EncodedStringWithOptions([])]
        return try props.rawData()
    }
}

struct Dispatch {
	let payloadEnc: NSData
	let senderPublicKey: PublicKey
	let ackKey: NSData
    
    func toJSON() throws -> NSData? {
        let props: JSON = ["payloadEnc": payloadEnc.base64EncodedStringWithOptions([]), "senderPublicKey": senderPublicKey.base64EncodedStringWithOptions([]), "ackKey": ackKey.base64EncodedStringWithOptions([])]
        return try props.rawData()
    }
}

public enum CryptoProviderError : ErrorType {
    case CannotDecryptMessage
    case CannotEncryptMessage
    case InvalidAckMessage
}

protocol CryptoProvider {
    static func genKeyPair() -> KeyPair
    static func encryptMessage(message: NSData, with keyPair: KeyPair, to recipient: PublicKey) throws -> NSData?
    static func decryptMessage(message: NSData, with keyPair: KeyPair) throws -> (payload: NSData?, from: PublicKey, ackMessage: NSData?)
    static func getMessageType(message: NSData) -> MessageType?
    static func checkBuffer(buffer: [NSData], against ackMessage: NSData) throws -> Int?
}

class SodiumCryptoProvider : CryptoProvider {
    static let sodium = Sodium()!
    
    static func genKeyPair() -> Box.KeyPair {
        return sodium.box.keyPair()!
    }
    
    static func encryptMessage(payload: NSData, with keyPair: KeyPair, to recipient: PublicKey) throws -> NSData? {
        let ephemeralKey = sodium.box.keyPair()!
        
        let uuid = ephemeralKey.publicKey
        let ackKey = sodium.secretBox.key()!
        let uuidEnc: NSData = sodium.secretBox.seal(uuid, secretKey: ackKey)!
        
        let dispatchKey = sodium.secretBox.key()!
        let dispatchKeyEnc: NSData = sodium.box.seal(dispatchKey, recipientPublicKey: recipient, senderSecretKey: ephemeralKey.secretKey)!
        
        let payloadEnc: NSData = sodium.box.seal(payload, recipientPublicKey: recipient, senderSecretKey: keyPair.secretKey)!
        
        var dispatch = Dispatch(payloadEnc: payloadEnc, senderPublicKey: keyPair.publicKey, ackKey: ackKey)
        let dispatchEnc: NSData = try sodium.secretBox.seal(dispatch.toJSON()!, secretKey: dispatchKey)!
        
        let message = ContentMessage(uuid: uuid, uuidEnc: uuidEnc, dispatchEnc: dispatchEnc, dispatchKeyEnc: dispatchKeyEnc)
        
        var messageContainer = MessageContainer(messageType: MessageType.Content, ackMessage: nil, contentMessage: message)
        return try messageContainer.toJSON()!
    }
    
    static func decryptMessage(message: NSData, with keyPair: KeyPair) throws -> (payload: NSData?, from: PublicKey, ackMessage: NSData?) {
        let messageContainer = JSON(data: message)
        
        let contentMessageData = NSData(base64EncodedString: messageContainer["contentMessage"].string!, options: [])
        let contentMessage = JSON(data:contentMessageData!)
        if let
            dispatchKey = try sodium.box.open(
                NSData(base64EncodedString:contentMessage["dispatchKeyEnc"].string!, options:[])!,
                senderPublicKey: NSData(base64EncodedString:contentMessage["uuid"].string!, options:[])!,recipientSecretKey: keyPair.secretKey),
            dispatchData = try sodium.secretBox.open(NSData(base64EncodedString:contentMessage["dispatchEnc"].string!, options: [])!, secretKey: dispatchKey)
        {
          
            let dispatch = JSON(data: dispatchData)
          
            if let payload = try sodium.box.open(NSData(base64EncodedString:dispatch["payloadEnc"].string!, options: [])!, senderPublicKey: NSData(base64EncodedString:dispatch["senderPublicKey"].string!, options: [])!, recipientSecretKey: keyPair.secretKey) {
                let ackMessage = try AckMessage(uuid: NSData(base64EncodedString:contentMessage["uuid"].string!, options: [])!, ackKey: NSData(base64EncodedString:dispatch["ackKey"].string!, options: [])!)
                var messageContainer = MessageContainer(messageType: MessageType.Ack, ackMessage: ackMessage, contentMessage: nil)
                
                return try (payload: payload, from: NSData(base64EncodedString:dispatch["senderPublicKey"].string!, options: [])!, ackMessage: messageContainer.toJSON()!)
            } else {
                throw CryptoProviderError.CannotDecryptMessage
            }
        } else {
            throw CryptoProviderError.CannotDecryptMessage
        }
    }
    
    static func getMessageType(message: NSData) -> MessageType? {
        let messageContainer = JSON(data: message)
        
        return MessageType(rawValue: messageContainer["messageType"].int!)
    }
    
    static func checkBuffer(buffer: [NSData], against ackMessage: NSData) throws -> Int? {
        let ackMessageContainer = JSON(data: ackMessage)
        let ackMessageData = NSData(base64EncodedString:ackMessageContainer["ackMessage"].string!, options: [])!
        let ackMessage = JSON(data:ackMessageData)
        
        for (index, message) in buffer.enumerate() {
            let messageContainer = JSON(data: message)
            let contentMessageData = NSData(base64EncodedString:messageContainer["contentMessage"].string!, options:[])!
            let contentMessage = JSON(data:contentMessageData)
            
            if (contentMessage["uuid"].string == ackMessage["uuid"].string) {
                let keyCheck = sodium.secretBox.open(NSData(base64EncodedString:contentMessage["uuidEnc"].string!, options: [])!, secretKey: NSData(base64EncodedString:ackMessage["ackKey"].string!, options: [])!)
                if try (keyCheck == NSData(base64EncodedString:contentMessage["uuid"].string!, options: [])) {
                    return index
                } else {
                    throw CryptoProviderError.InvalidAckMessage
                }
            }
        }
        
        return nil
    }

}

