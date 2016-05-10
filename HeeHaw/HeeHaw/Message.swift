//
//  Message.swift
//  HeeHaw
//
//  Created by Ankush Gupta on 5/8/16.
//  Copyright © 2016 Ankush Gupta. All rights reserved.
//

import Foundation
import CoreData

@objc(Message)
class Message: NSManagedObject {
    
    @NSManaged var alias: String
    @NSManaged var publicKey: String
    @NSManaged var outgoing: Bool
    @NSManaged var delivered: Bool
    @NSManaged var text: String
    @NSManaged var timestamp: NSTimeInterval
    
    class func createInManagedObjectContext(moc: NSManagedObjectContext, alias: String, publicKey: String, text: String, outgoing: Bool, delivered: Bool, timestamp: NSTimeInterval) -> Message {
        let newItem = NSEntityDescription.insertNewObjectForEntityForName("Message", inManagedObjectContext: moc) as! Message
        
        newItem.alias = alias
        newItem.publicKey = publicKey
        newItem.text = text
        newItem.outgoing = outgoing
        newItem.delivered = delivered
        newItem.timestamp = timestamp
        
        return newItem
    }
    
}