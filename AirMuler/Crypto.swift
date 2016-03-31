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

public enum CryptoProviderError : ErrorType {
    case CannotDecryptMessage
    case CannotEncryptMessage
}

protocol CryptoProvider {
    static func genKeyPair() -> KeyPair
    static func encryptMessage(message: NSData?, with keyPair: KeyPair?, to receipient: PublicKey) -> NSData?
    static func decryptMessage(message: NSData?, with keyPair: KeyPair?) throws -> (message: NSData?, from: PublicKey, time: NSDate)
}

class SodiumCryptoProvider : CryptoProvider {
    static let sodium = Sodium()!
    
    static func genKeyPair() -> Box.KeyPair {
        // TODO(jlmart88)
        return sodium.box.keyPair()!
    }
    
    static func encryptMessage(message: NSData?, with keyPair: KeyPair?, to receipient: PublicKey) -> NSData? {
        // TODO(jlmart88)
        return nil
    }
    
    static func decryptMessage(message: NSData?, with keyPair: KeyPair?) throws -> (message: NSData?, from: PublicKey, time: NSDate) {
        // TODO(jlmart(88)
        throw CryptoProviderError.CannotDecryptMessage
    }
}
