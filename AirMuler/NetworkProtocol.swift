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

class BufferItem {
    var packetItem : DataPacket
    var receiveTime : NSDate
    
    init(packet : DataPacket, rTime:NSDate) {
        self.packetItem = packet
        self.receiveTime = rTime
    }
}

public class NetworkProtocol: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    public static let sharedInstance : NetworkProtocol = {
        var keyPair : KeyPair
        
        let defaults = NSUserDefaults.standardUserDefaults()
        if let publicKey = defaults.objectForKey("public_key") as? PublicKey, secretKey = defaults.objectForKey("secret_key") as? SecretKey {
            keyPair = KeyPair(publicKey: publicKey, secretKey: secretKey)
            print("Using previously generated keypair")
        } else {
            print("Generating keypair...")
            
            keyPair = SodiumCryptoProvider.genKeyPair()
            
            defaults.setObject(keyPair.secretKey, forKey: "secret_key")
            defaults.setObject(keyPair.publicKey, forKey: "public_key")
            
            print("Done generating keypair!")
        }
    
        return NetworkProtocol(keyPair: keyPair)
    }()
    
    var advertiser : MCNearbyServiceAdvertiser!
    var session : MCSession!
    var peerID: MCPeerID!
    var browser : MCNearbyServiceBrowser!
    
    var buffer : [BufferItem]
    var keyPair : KeyPair
    public var delegate : NetworkProtocolDelegate?
    
    init(keyPair: KeyPair) {
        self.buffer = []
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
        do {
            if let encrypted = try SodiumCryptoProvider.encryptMessage(message, with: self.keyPair, to: recipient) {
                let packet = DataPacket(blob: encrypted, ttl: NetworkProtocolConstants.defaultTTL)
                let item = BufferItem(packet: packet, rTime: NSDate())
                
                self.buffer.append(item)
                try self.session.sendData(item.packetItem.serialize(), toPeers: self.session.connectedPeers, withMode: .Reliable)
                trimBuffer()
            }
        } catch {
            print("Error sending message: \(message)")
        }

    }
    
    private func inBuffer(packet : DataPacket) -> Bool {
        return self.buffer.contains({ $0.packetItem.hasSameBlob(packet) })
    }
    
    private func trimBuffer() {
        print("Buffer size is now \(buffer.count)")
        let remove = buffer.count - NetworkProtocolConstants.maxBufferLength
        if (remove > 0) {
            print("Trimming buffer...")
            buffer.removeRange(0..<remove)
        }
    }
    
    private func logPeers() {
        print("Connected peers: \(session.connectedPeers.description)")
    }
    
    // MARK: MCSessionDelegate
    public func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
        print("Session state changed to \(state)")
        
        if state == .Connected {
            for item in self.buffer {
                do {
                    try self.session.sendData(item.packetItem.serialize(), toPeers: [peerID], withMode: .Reliable)
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
        
        do {
            let (decryptedPayLoad, sender, ackMessage) = try SodiumCryptoProvider.decryptMessage(packet.blob, with: self.keyPair)
            
            if let payload = decryptedPayLoad {
                print("Successfully decrypted message \(payload) from \(sender)")
                delegate?.receivedMessage(payload, from: sender)
            }
            

        } catch {
            if packet.decrementTTL() {
                if !inBuffer(packet) {
                    print("Propogating message by adding to our buffer")
                    buffer.append(BufferItem(packet: packet, rTime: NSDate()))
                    trimBuffer()
                }
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