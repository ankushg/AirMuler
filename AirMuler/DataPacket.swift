//
//  DataPacket.swift
//  AirMuler
//
//  Created by Ankush Gupta on 3/30/16.
//  Copyright © 2016 AirMuler. All rights reserved.
//

import Foundation

public class DataPacket : NSObject, NSCoding {
    var blob : NSData
    var timeToLive : Int
    
    public init(blob : NSData, ttl : Int) {
        self.blob = blob
        self.timeToLive = ttl //hops
        super.init()
    }
    
    class func deserialize(dataInfo : NSData) -> DataPacket {
        return NSKeyedUnarchiver.unarchiveObjectWithData(dataInfo) as! DataPacket
    }
    
    public func serialize() -> NSData {
        return NSKeyedArchiver.archivedDataWithRootObject(self)
    }
    
    public required init(coder aDecoder: NSCoder) {
        self.blob = aDecoder.decodeObjectForKey("blob") as! NSData
        self.timeToLive = aDecoder.decodeIntegerForKey("ttl")
        super.init()
    }
    
    public func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeInteger(self.timeToLive, forKey: "ttl")
        aCoder.encodeObject(self.blob, forKey: "blob")
    }
    
    // returns false if dead
    public func decrementTTL() -> Bool {
        self.timeToLive -= 1
        return self.timeToLive > 0
    }
    
    public func hasSameBlob(other : DataPacket) -> Bool {
        return self.blob.isEqualToData(other.blob)
    }
}