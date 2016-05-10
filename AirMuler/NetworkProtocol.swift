//
//  NetworkProtocol.swift
//  AirMuler
//
//  Created by Ankush Gupta on 3/30/16.
//  Copyright © 2016 AirMuler. All rights reserved.
//

import Foundation
import MultipeerConnectivity

public protocol NetworkProtocolDelegate {
    func receivedMessage(message: NSData?, from publicKey: PublicKey)
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
        
        let extraKeyPair = SodiumCryptoProvider.genKeyPair()
        
        print("Extra keypair:")
        print(extraKeyPair.publicKey.base64EncodedStringWithOptions(NSDataBase64EncodingOptions.Encoding64CharacterLineLength))
    
        return NetworkProtocol(keyPair: keyPair)
    }()
    
    var advertiser : MCNearbyServiceAdvertiser!
    var session : MCSession!
    var peerID: MCPeerID!
    var browser : MCNearbyServiceBrowser!
    
    var contentBuffer : [DataPacket]
    var ackBuffer : [DataPacket]
    
    var keyPair : KeyPair
    public var delegate : NetworkProtocolDelegate?
    
    init(keyPair: KeyPair) {
        self.contentBuffer = []
        self.ackBuffer = []
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
    
    public func sendMessage(message: NSData, to recipient: PublicKey) {
        if let encrypted = SodiumCryptoProvider.encryptMessage(message, with: self.keyPair, to: recipient) {
            let packet = DataPacket(blob: encrypted, ttl: NetworkProtocolConstants.defaultTTL)
            self.acceptPacket(packet, to: &contentBuffer)
        }
    }
    
    private func checkBuffer(buffer: [DataPacket], for packet : DataPacket) -> Bool {
        return buffer.contains({ $0.hasSameBlob(packet) })
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
    
    func acceptPacket(packet: DataPacket, inout to buffer : [DataPacket]) {
        if packet.decrementTTL() {
            if !checkBuffer(buffer, for: packet) {
                print("Propogating packet by adding to buffer")
                buffer.append(packet)
                
                // broadcast to currently connected peers
                do {
                    try self.session.sendData(packet.serialize(), toPeers: self.session.connectedPeers, withMode: .Reliable)
                } catch {
                    print("Error sending packet!")
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
            do {
                if let contentIndex = try SodiumCryptoProvider.checkBuffer(contentBuffer.map( {$0.blob} ), against: blob) {
                    contentBuffer.removeAtIndex(contentIndex)
                    // TODO: notify delegate that message was acked?
                }
                self.acceptPacket(packet, to: &ackBuffer)
            } catch {
                // not a valid Ack. Ignore
            }
            
        case MessageType.Content:
            do {
                let (decryptedPayload, sender, ack) = try SodiumCryptoProvider.decryptMessage(blob, with: self.keyPair)
                if let payload = decryptedPayload {
                    // our message!
                    print("Successfully decrypted message \(payload) from \(sender)")
                    delegate?.receivedMessage(payload, from: sender)
                    
                    // ack the message!
                    if let ackBlob = ack {
                        let ackPacket = DataPacket(blob: ackBlob, ttl: NetworkProtocolConstants.defaultTTL)
                        self.acceptPacket(ackPacket, to: &ackBuffer)
                    }
                }
            } catch {
                // not our message -- retransmit
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