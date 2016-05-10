//
//  ViewController.swift
//  HeeHaw
//
//  Created by Ankush Gupta on 5/8/16.
//  Copyright © 2016 Ankush Gupta. All rights reserved.
//

import UIKit

import CoreData
import AirMuler
import SwiftyJSON
import CoreActionSheetPicker

class HeeHawViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, NetworkProtocolDelegate, UINavigationBarDelegate, LGChatControllerDelegate, UIPickerViewDataSource, ActionSheetCustomPickerDelegate{
    
    var networkingLayer : NetworkProtocol
    var chatController : LGChatController?
    var threadTable = UITableView(frame: CGRectZero, style: .Plain)
    
    var contacts : [String] = [] // pubKeys
    var messages : [String : [Message]] = [:] // pubKey -> [message]
    var aliases : [String : String] = [:] // pubKey -> alias
    
    var currentChatPubKey : String?
    
    required init?(coder aDecoder: NSCoder) {
        self.networkingLayer = NetworkProtocol.sharedInstance
        super.init(coder: aDecoder)
        self.networkingLayer.delegate = self
    }
    
    override init(nibName nibNameOrNil: String!, bundle nibBundleOrNil: NSBundle!) {
        self.networkingLayer = NetworkProtocol.sharedInstance
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.networkingLayer.delegate = self
    }
    
    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    lazy var managedObjectContext : NSManagedObjectContext? = {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
        return appDelegate.managedObjectContext
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        fetchMessages()
        
        let viewFrame = self.view.frame
        self.threadTable.frame = viewFrame
        self.view.addSubview(threadTable)
        
        self.threadTable.registerClass(ThreadTableViewCell.classForCoder(), forCellReuseIdentifier: "ThreadCell")
        self.threadTable.dataSource = self
        self.threadTable.delegate = self
        
        self.title = "🐴"
        let leftButton = UIBarButtonItem(barButtonSystemItem: .Add, target: self, action: #selector(addNewContact))
        self.navigationController?.topViewController?.navigationItem.leftBarButtonItem = leftButton
        let rightButton = UIBarButtonItem(barButtonSystemItem: .Compose, target: self, action: #selector(composeNewMessage))
        self.navigationController?.topViewController?.navigationItem.rightBarButtonItem = rightButton
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func addNewContact() {
        let alertController = UIAlertController(title: "Add a Contact", message: "", preferredStyle: UIAlertControllerStyle.Alert)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: nil)
        alertController.addAction(cancelAction)
        
        let saveAction = UIAlertAction(title: "Save", style: .Default, handler: {
            alert -> Void in
            
            let alias = (alertController.textFields![0] as UITextField).text as String!
            let pubKey = (alertController.textFields![1] as UITextField).text as String!
            
            if (!self.contacts.contains(pubKey)) {
                self.contacts.insert(pubKey, atIndex: 0)
            }
            
            if (self.messages[pubKey] == nil) {
                self.messages[pubKey] = []
            }
            
            self.aliases[pubKey] = alias!
            
            self.threadTable.reloadData()
        })
        
        alertController.addAction(saveAction)

        alertController.addTextFieldWithConfigurationHandler { (textField : UITextField!) -> Void in
            textField.placeholder = "Alias"
        }
        alertController.addTextFieldWithConfigurationHandler { (textField : UITextField!) -> Void in
            textField.placeholder = "Public Key"
        }
        
        
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    func composeNewMessage() {
        ActionSheetCustomPicker.showPickerWithTitle("Choose recipient", delegate: self, showCancelButton: true, origin: self.view)
    }
    
    func processNewMessage(message: Message) {
        var personMessages: [Message] = []
        if let messages = messages[message.publicKey] {
            personMessages = messages
        } else {
            self.contacts.insert(message.publicKey, atIndex: 0)
        }
        
        personMessages.append(message)
        aliases[message.publicKey] = message.alias
        
        messages[message.publicKey] = personMessages
    }
    
    func fetchMessages() {
        let fetchRequest = NSFetchRequest(entityName: "Message")
        let sortDescriptor = NSSortDescriptor(key: "timestamp", ascending: true)
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        messages = [:]
        contacts = []
        aliases = [:]
        
        do {
            try (managedObjectContext!.executeFetchRequest(fetchRequest) as? [Message])?.forEach(processNewMessage)
        } catch let error as NSError {
            print("Fetch failed: \(error.localizedDescription)")
        }
        
        self.threadTable.reloadData()
    }
    
    func saveMessage(message: String, with alias : String, isOutgoing: Bool, withKey publicKey: String, at time: NSDate) {
        if let moc = self.managedObjectContext {
            let newMessage = Message.createInManagedObjectContext(moc,
              peer: alias,
              publicKey: publicKey,
              text: message,
              outgoing: isOutgoing,
              contactDate: time)
            
            do {
                try moc.save()
                processNewMessage(newMessage)
                self.threadTable.reloadData()
            } catch let error as NSError {
                print("Unresolved error \(error), \(error.userInfo)")
                abort()
            }
        }
    }
    
    func showChatForCurrentPubKey() {
        if let pubKey = currentChatPubKey {
            print("Pushing Chat controller")
            
            chatController = LGChatController()
            chatController?.delegate = self
            
            chatController?.messages = getMessagesForPublicKey(pubKey)
            self.navigationController?.pushViewController(chatController!, animated: true)
            chatController?.title = getAliasFromPublicKey(pubKey)
        }
    }
    
    func getAliasFromPublicKey(publicKey : String) -> String {
        return aliases[publicKey] ?? publicKey
    }
    
    func getLGChatMessageForMessage(message: Message) -> LGChatMessage {
        let sender : LGChatMessage.SentBy = message.outgoing ? .User : .Opponent
        return LGChatMessage(content: message.text, sentBy: sender, timeStamp: message.timestamp.timeIntervalSinceNow)
    }
    
    func makeLGMessages(userMessages : [Message]) -> [LGChatMessage] {
        return userMessages.map(getLGChatMessageForMessage)
    }
    
    func getMessagesForPublicKey(publicKey : String) -> [LGChatMessage] {
        if let userMessages = self.messages[publicKey] {
            return makeLGMessages(userMessages)
        }
        return []
    }

    // MARK: UITableViewDataSource
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("ThreadCell", forIndexPath: indexPath) as! ThreadTableViewCell
        let contact = contacts[indexPath.row]
        
        cell.messagePeerLabel.text = getAliasFromPublicKey(contact)
        
        if let messageItem = messages[contact]?.last {
            cell.messageTextLabel.text = messageItem.text
        } else {
            cell.messageTextLabel.text = ""
        }
        
        return cell
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count;
    }
    
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return 80
    }
    
    // MARK: UITableViewDelegate
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        currentChatPubKey = contacts[indexPath.row]
        self.threadTable.deselectRowAtIndexPath(indexPath, animated: true)
        showChatForCurrentPubKey()
    }
    
    // MARK: UIPickerViewDataSource
    func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return contacts.count
    }
    
    func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return getAliasFromPublicKey(contacts[row])
    }
    
    //MARK: ActionSheetCustomPickerDelegate
    func actionSheetPicker(actionSheetPicker: AbstractActionSheetPicker!, configurePickerView pickerView: UIPickerView!) {
        pickerView.dataSource = self
    }
    
    func actionSheetPickerDidSucceed(actionSheetPicker: AbstractActionSheetPicker!, origin: AnyObject!) {
        if let picker = actionSheetPicker.pickerView as? UIPickerView {
            let row = picker.selectedRowInComponent(0)
            if (row > -1) {
                self.currentChatPubKey = contacts[row]
                self.showChatForCurrentPubKey()
            }            
        }
        
    }
    
    func actionSheetPickerDidCancel(actionSheetPicker: AbstractActionSheetPicker!, origin: AnyObject!) {
        // Do nothing
    }
    
    // MARK: LGChatControllerDelegate
    func chatController(chatController: LGChatController, didAddNewMessage message: LGChatMessage) {
        print("Added Message: \(message.content)")
    }
    
    func shouldChatController(chatController: LGChatController, addMessage message: LGChatMessage) -> Bool {
        do {
            let actualPubKey: NSData? = NSData(base64EncodedString: currentChatPubKey!, options: .IgnoreUnknownCharacters)
            let json : JSON = ["message": message.content, "timestamp": NSDate().timeIntervalSince1970]
            let data = try json.rawData()
            print("Sending raw data \(data)")
            
            try networkingLayer.sendMessage(data, to: actualPubKey!)
        } catch let error as NSError {
            print("Unresolved error \(error), \(error.userInfo)")
            abort()
        }
        
        saveMessage(message.content, with: getAliasFromPublicKey(currentChatPubKey!), isOutgoing: true, withKey: currentChatPubKey!, at: NSDate())
        
        return true
    }
    
    // MARK: NetworkProtocolDelegate
    func receivedMessage(messageData: NSData?, from publicKey: PublicKey) {
        let messageObj = JSON(data: messageData!)
        
        if let messageText = messageObj["message"].string, timestamp = messageObj["timestamp"].double {
            let messagePublicKey = publicKey.base64EncodedStringWithOptions([])
            let alias = getAliasFromPublicKey(messagePublicKey)
            let time = NSDate(timeIntervalSince1970: timestamp)
            
            // Check if duplicate of already delivered message
            if let previousMessages = self.messages[messagePublicKey] {
                for message in previousMessages {
                    let sameTime = message.timestamp.compare(time) == .OrderedSame
                    if messageText == message.text && sameTime {
                        return
                    }
                }
            }
            
            saveMessage(messageText, with: alias, isOutgoing: false, withKey: messagePublicKey, at: time)
            
            if (messagePublicKey == currentChatPubKey) {
                print("Got a new message for \(alias): \(messageText)")
                let message = LGChatMessage(content: messageText, sentBy: .Opponent)
                dispatch_async(dispatch_get_main_queue(), {
                    self.chatController?.addNewMessage(message)
                })
            }
        }
    }
    
    // MARK: NetworkProtocolDelegate
    func acknowledgedReceiptOfMessage(message: NSData?) {
        
    }
}

