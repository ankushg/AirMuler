//
//  Crypto.swift
//  AirMuler
//
//  Created by Ankush Gupta on 3/29/16.
//  Copyright © 2016 AirMuler. All rights reserved.
//

import Foundation
import Sodium

public typealias PublicKey = Box.PublicKey
public typealias SecretKey = Box.SecretKey
public typealias KeyPair = Box.KeyPair

extension KeyPair {
    init(publicKey: PublicKey, secretKey: SecretKey) {
        self.publicKey = publicKey
        self.secretKey = secretKey
    }
}

enum MessageType: Int8 {
    case Content
    case Ack
}
    
struct MessageContainer {
	let messageType: MessageType?
	let ackMessage: AckMessage?
	let contentMessage: ContentMessage?
}

struct ContentMessage {
	let uuid: PublicKey
	let uuidEnc: NSData
	let dispatchEnc: NSData
	let dispatchKeyEnc: NSData
}

struct AckMessage {
	let uuid: PublicKey;
	let ackKey: NSData;
}

struct Dispatch {
	let payload: NSData?
	let signature: NSData?
	let senderPublicKey: PublicKey?
	let ackKey: NSData?
}

public enum CryptoProviderError : ErrorType {
    case CannotDecryptMessage
    case CannotEncryptMessage
}

protocol CryptoProvider {
    static func genKeyPair() -> KeyPair
    static func encryptMessage(message: NSData, with keyPair: KeyPair, to recipient: PublicKey) -> NSData?
    static func decryptMessage(message: NSData, with keyPair: KeyPair) throws -> (payload: NSData?, from: PublicKey, ackMessage: NSData?)
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
        
        let signature: NSData = sodium.sign.signature(payload, secretKey: keyPair.secretKey)!
        
        var dispatch = Dispatch(payload: payload, signature: signature, senderPublicKey: keyPair.publicKey, ackKey: ackKey)
        let dispatchEnc: NSData = sodium.secretBox.seal(NSData(bytes: &dispatch, length: sizeof(Dispatch)), secretKey: dispatchKey)!
        
        let message = ContentMessage(uuid: uuid, uuidEnc: uuidEnc, dispatchEnc: dispatchEnc, dispatchKeyEnc: dispatchKeyEnc)
        
        var messageContainer = MessageContainer(messageType: MessageType.Content, ackMessage: nil, contentMessage: message)
        return NSData(bytes: &messageContainer, length: sizeof(MessageContainer))
    }
    
    static func decryptMessage(message: NSData, with keyPair: KeyPair) throws -> (payload: NSData?, from: PublicKey, ackMessage: NSData?) {
        var messageContainer: MessageContainer = MessageContainer(messageType: MessageType.Ack, ackMessage: nil, contentMessage: nil)
        message.getBytes(&messageContainer, length: sizeof(MessageContainer))
        
        if (messageContainer.messageType != MessageType.Content) {
            throw CryptoProviderError.CannotDecryptMessage
        }
        
        let contentMessage = messageContainer.contentMessage!
        
        if let
            dispatchKey = sodium.box.open(contentMessage.dispatchKeyEnc, senderPublicKey: contentMessage.uuid, recipientSecretKey: keyPair.secretKey),
            dispatchData = sodium.secretBox.open(contentMessage.dispatchEnc, secretKey: dispatchKey)
        {
          
            var dispatch: Dispatch = Dispatch(payload: nil, signature: nil, senderPublicKey: nil, ackKey: nil)
            dispatchData.getBytes(&dispatch, length: sizeof(Dispatch))
          
            if (sodium.sign.verify(dispatch.payload!, publicKey: dispatch.senderPublicKey!, signature: dispatch.signature!)) {
                let ackMessage = AckMessage(uuid: contentMessage.uuid, ackKey: dispatch.ackKey!)
                var messageContainer = MessageContainer(messageType: MessageType.Ack, ackMessage: ackMessage, contentMessage: nil)
                
                return (payload: dispatch.payload, from: dispatch.senderPublicKey!, ackMessage: NSData(bytes: &messageContainer, length: sizeof(MessageContainer)))
            } else {
                throw CryptoProviderError.CannotDecryptMessage
            }
        } else {
            throw CryptoProviderError.CannotDecryptMessage
        }
    }    
}

