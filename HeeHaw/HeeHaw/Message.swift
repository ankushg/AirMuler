//
//  Message.swift
//  HeeHaw
//
//  Created by Ankush Gupta on 5/8/16.
//  Copyright © 2016 Ankush Gupta. All rights reserved.
//

import Foundation
import CoreData

class Message: NSManagedObject {
    
    @NSManaged var alias: String
    @NSManaged var publicKey: String
    @NSManaged var outgoing: Bool
    @NSManaged var text: String
    @NSManaged var timestamp: NSDate
    
    class func createInManagedObjectContext(moc: NSManagedObjectContext, peer: String, publicKey: String, text: String, outgoing: Bool, contactDate: NSDate) -> Message {
        let newItem = NSEntityDescription.insertNewObjectForEntityForName("Message", inManagedObjectContext: moc) as! Message
        
        newItem.alias = peer
        newItem.publicKey = publicKey
        newItem.text = text
        newItem.outgoing = outgoing
        newItem.timestamp = contactDate
        
        return newItem
    }
    
}