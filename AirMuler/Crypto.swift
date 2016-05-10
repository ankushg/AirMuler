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
    
    func toJSON() -> NSData? {
        var props: NSDictionary = [:]
        if messageType == MessageType.Ack {
            props = ["messageType": messageType.rawValue, "ackMessage": ackMessage!.toJSON()!]
        } else if messageType == MessageType.Content {
            props = ["messageType": messageType.rawValue, "contentMessage": contentMessage!.toJSON()!]
        }
        do {
            let jsonData = try NSJSONSerialization.dataWithJSONObject(props, options: [])
            return jsonData
        } catch let error {
            print("error converting to json: \(error)")
            return nil
        }
    }
}

struct ContentMessage {
	let uuid: PublicKey
	let uuidEnc: NSData
	let dispatchEnc: NSData
	let dispatchKeyEnc: NSData
    
    func toJSON() -> NSData? {
        let props = ["uuid": uuid, "uuidEnc": uuidEnc, "dispatchEnc": dispatchEnc, "dispatchKeyEnc": dispatchKeyEnc]
        do {
            let jsonData = try NSJSONSerialization.dataWithJSONObject(props, options: [])
            return jsonData
        } catch let error {
            print("error converting to json: \(error)")
            return nil
        }
    }
}

struct AckMessage {
	let uuid: PublicKey;
	let ackKey: NSData;
    
    func toJSON() -> NSData? {
        let props = ["uuid": uuid, "ackKey": ackKey]
        do {
            let jsonData = try NSJSONSerialization.dataWithJSONObject(props, options: [])
            return jsonData
        } catch let error {
            print("error converting to json: \(error)")
            return nil
        }
    }
}

struct Dispatch {
	let payloadEnc: NSData
	let senderPublicKey: PublicKey
	let ackKey: NSData
    
    func toJSON() -> NSData? {
        let props = ["payloadEnc": payloadEnc, "senderPublicKey": senderPublicKey, "ackKey": ackKey]
        do {
            let jsonData = try NSJSONSerialization.dataWithJSONObject(props, options: [])
            return jsonData
        } catch let error {
            print("error converting to json: \(error)")
            return nil
        }
    }
}

public enum CryptoProviderError : ErrorType {
    case CannotDecryptMessage
    case CannotEncryptMessage
    case InvalidAckMessage
}

protocol CryptoProvider {
    static func genKeyPair() -> KeyPair
    static func encryptMessage(message: NSData, with keyPair: KeyPair, to recipient: PublicKey) -> NSData?
    static func decryptMessage(message: NSData, with keyPair: KeyPair) throws -> (payload: NSData?, from: PublicKey, ackMessage: NSData?)
    static func getMessageType(message: NSData) -> MessageType?
    static func checkBuffer(buffer: [NSData], against ackMessage: NSData) throws -> Int?
}

class SodiumCryptoProvider : CryptoProvider {
    static let sodium = Sodium()!
    
    static func genKeyPair() -> Box.KeyPair {
        return sodium.box.keyPair()!
    }
    
    static func encryptMessage(payload: NSData, with keyPair: KeyPair, to recipient: PublicKey) -> NSData? {
        let ephemeralKey = sodium.box.keyPair()!
        
        let uuid = ephemeralKey.publicKey
        let ackKey = sodium.secretBox.key()!
        let uuidEnc: NSData = sodium.secretBox.seal(uuid, secretKey: ackKey)!
        
        let dispatchKey = sodium.secretBox.key()!
        let dispatchKeyEnc: NSData = sodium.box.seal(dispatchKey, recipientPublicKey: recipient, senderSecretKey: ephemeralKey.secretKey)!
        
        let payloadEnc: NSData = sodium.box.seal(payload, recipientPublicKey: recipient, senderSecretKey: keyPair.secretKey)!
        
        var dispatch = Dispatch(payloadEnc: payloadEnc, senderPublicKey: keyPair.publicKey, ackKey: ackKey)
        let dispatchEnc: NSData = sodium.secretBox.seal(dispatch.toJSON()!, secretKey: dispatchKey)!
        
        let message = ContentMessage(uuid: uuid, uuidEnc: uuidEnc, dispatchEnc: dispatchEnc, dispatchKeyEnc: dispatchKeyEnc)
        
        var messageContainer = MessageContainer(messageType: MessageType.Content, ackMessage: nil, contentMessage: message)
        return messageContainer.toJSON()!
    }
    
    static func decryptMessage(message: NSData, with keyPair: KeyPair) throws -> (payload: NSData?, from: PublicKey, ackMessage: NSData?) {
        let messageContainer = JSON(data: message)
        
        let contentMessageData = try messageContainer["contentMessage"].rawData()
        let contentMessage = JSON(data:contentMessageData)
        if let
            dispatchKey = try sodium.box.open(contentMessage["dispatchKeyEnc"].rawData(), senderPublicKey: contentMessage["uuid"].rawData(), recipientSecretKey: keyPair.secretKey),
            dispatchData = try sodium.secretBox.open(contentMessage["dispatchEnc"].rawData(), secretKey: dispatchKey)
        {
          
            let dispatch = JSON(data: dispatchData)
          
            if let payload = try sodium.box.open(dispatch["payloadEnc"].rawData(), senderPublicKey: dispatch["senderPublicKey"].rawData(), recipientSecretKey: keyPair.secretKey) {
                let ackMessage = try AckMessage(uuid: contentMessage["uuid"].rawData(), ackKey: dispatch["ackKey"].rawData())
                var messageContainer = MessageContainer(messageType: MessageType.Ack, ackMessage: ackMessage, contentMessage: nil)
                
                return try (payload: payload, from: dispatch["senderPublicKey"].rawData(), ackMessage: messageContainer.toJSON()!)
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
        let ackMessageData = try ackMessageContainer["ackMessage"].rawData()
        let ackMessage = JSON(data:ackMessageData)
        
        for (index, message) in buffer.enumerate() {
            let messageContainer = JSON(data: message)
            let contentMessageData = try messageContainer["contentMessage"].rawData()
            let contentMessage = JSON(data:contentMessageData)
            
            if try (contentMessage["uuid"].rawData() == ackMessage["uuid"].rawData()) {
                let keyCheck = try sodium.secretBox.open(contentMessage["uuidEnc"].rawData(), secretKey: ackMessage["ackKey"].rawData())
                if try (keyCheck == contentMessage["uuid"].rawData()) {
                    return index
                } else {
                    throw CryptoProviderError.InvalidAckMessage
                }
            }
        }
        
        return nil
    }

}

