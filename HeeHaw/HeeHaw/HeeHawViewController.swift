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
    var chatController : LGChatController = LGChatController()
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
        
        chatController.delegate = self
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
            
            if((self.aliases[pubKey] == nil)) {
                self.contacts.append(pubKey)
                self.aliases[pubKey] = alias!
                self.messages[pubKey!] = []
            } else {
                print("Already have alias \(self.aliases[pubKey]) for \(pubKey)")
            }
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
    
    func fetchMessages() {
        let fetchRequest = NSFetchRequest(entityName: "Message")
        let sortDescriptor = NSSortDescriptor(key: "timestamp", ascending: true)
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        messages = [:]
        contacts = []
        aliases = [:]
        
        do {
            if let allMessages = try managedObjectContext!.executeFetchRequest(fetchRequest) as? [Message] {
                for message in allMessages {
                    var personMessages: [Message] = []
                    if let messages = messages[message.publicKey] {
                        personMessages = messages
                    } else {
                        self.contacts.insert(message.publicKey, atIndex: 0)
                    }
                    
                    if(message.alias != "Me") {
                        aliases[message.publicKey] = message.alias
                    }
                    
                    personMessages.append(message)
                    messages[message.publicKey] = personMessages
                }
            }
        } catch let error as NSError {
            print("Fetch failed: \(error.localizedDescription)")
        }
        
        self.threadTable.reloadData()
    }
    
    func showChatForCurrentPubKey() {
        if let pubKey = currentChatPubKey {
            print("Pushing Chat controller")
            chatController.messages = getMessagesForPublicKey(pubKey)
            self.navigationController?.pushViewController(chatController, animated: true)
            chatController.title = getAliasFromPublicKey(pubKey)
        }
    }
    
    func saveMessage(message: String, from sender : String, withKey publicKey: String, at time: NSDate) {
        if let moc = self.managedObjectContext {
            Message.createInManagedObjectContext(moc,
                                                 peer: sender,
                                                 publicKey: publicKey,
                                                 text: message,
                                                 outgoing: sender == "Me" ? true : false,
                                                 contactDate: time
            )
            
            do {
                try moc.save()
            } catch let error as NSError {
                print("Unresolved error \(error), \(error.userInfo)")
                abort()
            }
        }
    }
    
    func getAliasFromPublicKey(publicKey : String) -> String {
        return aliases[publicKey] ?? publicKey
    }
    
    func getLGChatMessageForMessage(message: Message) -> LGChatMessage {
        let sender : LGChatMessage.SentBy = message.outgoing ? .Opponent : .User
        return LGChatMessage(content: message.text, sentBy: sender)
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
        
        let messageItem = messages[contacts[indexPath.row]]!.last!

        cell.messagePeerLabel.text = messageItem.alias
        cell.messageTextLabel.text = messageItem.text
        
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
            
            try networkingLayer.sendMessage(data, to: actualPubKey!)
        } catch let error as NSError {
            print("Unresolved error \(error), \(error.userInfo)")
            abort()
        }
        
        saveMessage(message.content, from: "Me", withKey: currentChatPubKey!, at: NSDate())
        
        return true
    }
    
    // MARK: NetworkProtocolDelegate
    func receivedMessage(messageData: NSData?, from publicKey: PublicKey) {
        let messageObj = JSON(data:messageData!)
        
        if let messageText = messageObj["message"].string, timestamp = messageObj["timestamp"].double {
            let messagePublicKey = publicKey.base64EncodedStringWithOptions([])
            let time = NSDate(timeIntervalSince1970: timestamp)
            
            if let previousMessages = self.messages[messagePublicKey] {
                for message in previousMessages {
                    let sameTime = message.timestamp.compare(time) == .OrderedSame
                    if messageText == message.text && sameTime {
                        return
                    }
                }
            }
            
            saveMessage(messageText, from: getAliasFromPublicKey(messagePublicKey), withKey: messagePublicKey, at: time)
            self.fetchMessages()
            
            if (messagePublicKey == currentChatPubKey) {
                self.chatController.addNewMessage(LGChatMessage(content: messageText, sentBy: .Opponent))
            }
        }
    }
}

