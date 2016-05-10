//
//  NetworkProtocol.swift
//  AirMuler
//
//  Created by Ankush Gupta on 3/30/16.
//  Copyright © 2016 AirMuler. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import SwiftyJSON

@objc public protocol NetworkProtocolDelegate {
    optional func connectedWithKey(key: NSData?)
    func receivedMessage(message: NSData?, from publicKey: PublicKey)
    optional func acknowledgedDeliveryOfMessage(message: NSData?, to publicKey: PublicKey)
}

struct NetworkProtocolConstants {
    static let maxBufferLength = 20
    static let defaultTTL = 10 // hops
    static let serviceType = "pf-connector"
}

public class NetworkProtocol: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    public static let sharedInstance : NetworkProtocol = {
        var keyPair : KeyPair
        
        let defaults = NSUserDefaults.standardUserDefaults()
        if let publicKey = defaults.objectForKey("public_key") as? PublicKey, secretKey = defaults.objectForKey("secret_key") as? SecretKey {
            keyPair = KeyPair(publicKey: publicKey, secretKey: secretKey)
            print("Using previously generated keypair")
            print(publicKey.base64EncodedStringWithOptions(NSDataBase64EncodingOptions.Encoding64CharacterLineLength))
        } else {
            print("Generating keypair...")
            
            keyPair = SodiumCryptoProvider.genKeyPair()
            
            defaults.setObject(keyPair.secretKey, forKey: "secret_key")
            defaults.setObject(keyPair.publicKey, forKey: "public_key")
            
            print("Done generating keypair!")
            print(keyPair.publicKey.base64EncodedStringWithOptions(NSDataBase64EncodingOptions.Encoding64CharacterLineLength))
        }
        return NetworkProtocol(keyPair: keyPair)
    }()
    
    var advertiser : MCNearbyServiceAdvertiser!
    var session : MCSession!
    var peerID: MCPeerID!
    var browser : MCNearbyServiceBrowser!
    
    var contentBuffer : [DataPacket]
    var ackBuffer : [DataPacket]
    var sentBuffer : [DataPacket]
    
    
    var keyPair : KeyPair
    public var delegate : NetworkProtocolDelegate? {
        willSet {
            newValue?.connectedWithKey?(keyPair.publicKey)
        }
    }
    
    init(keyPair: KeyPair) {
        self.contentBuffer = []
        self.ackBuffer = []
        self.sentBuffer = []
        self.keyPair = keyPair;
        self.peerID = MCPeerID(displayName: UIDevice.currentDevice().name)
        
        super.init()
        
        self.session = MCSession(peer: peerID)
        self.session.delegate = self
        
        self.advertiser = MCNearbyServiceAdvertiser(peer: self.peerID, discoveryInfo: nil, serviceType: NetworkProtocolConstants.serviceType)
        self.advertiser.delegate = self
        self.advertiser.startAdvertisingPeer()
        
        self.browser = MCNearbyServiceBrowser(peer: self.peerID, serviceType: NetworkProtocolConstants.serviceType)
        self.browser.delegate = self;
        
        self.browser.startBrowsingForPeers()
        print("Started browsing for peers!")
    }
    
    public func sendMessage(message: NSData, to recipient: PublicKey) throws {
        if let encrypted = try SodiumCryptoProvider.encryptMessage(message, with: self.keyPair, to: recipient) {
            let packet = DataPacket(blob: encrypted, ttl: NetworkProtocolConstants.defaultTTL)
            self.acceptPacket(packet, to: &contentBuffer)
            
            let sentBlob: JSON = ["encrypted": encrypted.base64EncodedStringWithOptions([]), "message": message.base64EncodedStringWithOptions([]), "recipient": recipient.base64EncodedStringWithOptions([])]
            let sentPacket = try DataPacket(blob: sentBlob.rawData(), ttl: NetworkProtocolConstants.defaultTTL)
            self.acceptPacket(sentPacket, to: &sentBuffer, shouldBroadcast: false)
        }
    }
    
    private func checkBuffer(buffer: [DataPacket], for packet : DataPacket) -> Bool {
        return buffer.contains({ $0.hasSameBlob(packet) })
    }
    
    private func checkSentBuffer(for message: DataPacket) -> (message: NSData, recipient: PublicKey)? {
        for (index, packet) in sentBuffer.enumerate() {
            let blobJSON = JSON(data:packet.blob)
            let encrypted = NSData(base64EncodedString: blobJSON["encrypted"].string!, options: [])
            if SodiumCryptoProvider.checkMessage(encrypted!, against: message.blob) {
                sentBuffer.removeAtIndex(index)
                return (NSData(base64EncodedString: blobJSON["message"].string!, options: [])!, NSData(base64EncodedString: blobJSON["recipient"].string!, options: [])!)
            }
        }
        return nil
    }
    
    private func trimBuffer(inout buffer: [DataPacket], to maxLength : Int) {
        print("Buffer size is now \(buffer.count)")
        let remove = buffer.count - maxLength
        if (remove > 0) {
            print("Trimming buffer...")
            buffer.removeRange(0..<remove)
        }
    }
    
    private func logPeers() {
        print("Connected peers: \(session.connectedPeers.description)")
    }
    
    func acceptPacket(packet: DataPacket, inout to buffer : [DataPacket], shouldBroadcast: Bool = true) {
        if packet.decrementTTL() {
            if checkBuffer(buffer, for: packet) {
               print("Not adding duplicate packet to buffer")
            } else {
                print("Propogating packet by adding to buffer")
                buffer.append(packet)
                
                if shouldBroadcast {
                    // broadcast to currently connected peers
                    do {
                        try self.session.sendData(packet.serialize(), toPeers: self.session.connectedPeers, withMode: .Reliable)
                    } catch {
                        print("Error sending packet!")
                    }
                }
                
                trimBuffer(&buffer, to: NetworkProtocolConstants.maxBufferLength)
            }
        }
    }
    
    // MARK: MCSessionDelegate
    public func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
        print("Session state changed to \(state)")
        
        if state == .Connected {
            for item in self.contentBuffer + self.ackBuffer {
                do {
                    try self.session.sendData(item.serialize(), toPeers: [peerID], withMode: .Reliable)
                } catch let error as NSError {
                    print("Error sending data to \(peerID.displayName): \(error.localizedDescription)")
                }
            }
        }
        self.logPeers()
    }
    
    public func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
        print("Received data from \(peerID.displayName)")
        
        let packet = DataPacket.deserialize(data)
        let blob = packet.blob
        
        switch SodiumCryptoProvider.getMessageType(blob)! {
        case MessageType.Ack:
            print("Received ack!")
            do {
                if let contentIndex = try SodiumCryptoProvider.checkBuffer(contentBuffer.map( {$0.blob} ), against: blob) {
                    let packet = contentBuffer.removeAtIndex(contentIndex)
                    print("Received ack for message!")
                    
                    if let (message, recipient) = checkSentBuffer(for: packet){
                        self.delegate?.acknowledgedDeliveryOfMessage?(message, to: recipient)
                    } else {
                        print("Ack is not for message sent by us")
                    }
                } else {
                    print("Ack did not match any message in buffer")
                }
                
                print("Saving ack for broadcast!")
                self.acceptPacket(packet, to: &ackBuffer)
            } catch {
                // not a valid Ack. Ignore
                print("Received invalid ack message")
            }
            
        case MessageType.Content:
            print("Received message!")
            do {
                let (decryptedPayload, sender, ack) = try SodiumCryptoProvider.decryptMessage(blob, with: self.keyPair)
                if let payload = decryptedPayload {
                    // our message!
                    print("Successfully decrypted message \(payload) from \(sender)")
                    delegate?.receivedMessage(payload, from: sender)
                    
                    // ack the message!
                    if let ackBlob = ack {
                        print("Sending ack for message!")
                        let ackPacket = DataPacket(blob: ackBlob, ttl: NetworkProtocolConstants.defaultTTL)
                        self.acceptPacket(ackPacket, to: &ackBuffer)
                    }
                }
            } catch {
                // not our message -- retransmit
                print("Saving message for broadcast!")
                self.acceptPacket(packet, to: &contentBuffer)
            }
        }
    }
    
    public func session(session: MCSession, didReceiveStream stream: NSInputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Do nothing
    }
    
    public func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress) {
        // Do nothing
    }
    
    public func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {
        // Do nothing
    }
    
    // MARK: MCNearbyServiceBrowser
    public func browser(browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("Found peer \(peerID.displayName)")
        self.browser.invitePeer(peerID, toSession: self.session, withContext: nil, timeout: 0)
        print("Invited peer \(peerID.displayName)")
    }
    
    public func browser(browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: NSError) {
        print("Browser \(self.peerID.displayName) did not start browsing for peers with error \(error.localizedDescription)")
    }
    
    public func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer \(peerID.displayName)")
        self.logPeers()
    }
    
    // MARK: MCNearbyServiceAdvertiserDelegate
    public func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void) {
        print("Received invitation from \(peerID.displayName)")
        invitationHandler(true, self.session)
        print("Accepted invitation from \(peerID.displayName)")
    }
    
    public func advertiser(advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: NSError) {
        print("Advertiser \(self.peerID.displayName) did not start advertising with error \(error.localizedDescription)")
    }
}