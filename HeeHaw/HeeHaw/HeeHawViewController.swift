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

class HeeHawViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, NetworkProtocolDelegate, UINavigationBarDelegate, LGChatControllerDelegate, UIPickerViewDelegate, UIPickerViewDataSource {
    let IOS_BAR_HEIGHT : Float = 20.0
    let ROWS_PER_SCREEN : Float = 8.0
    let NAV_BAR_HEIGHT : Float = 64.0
    
    var networkingLayer : NetworkProtocol
    var chatController : LGChatController = LGChatController()
    var messageTable = UITableView(frame: CGRectZero, style: .Plain)
    
    var contacts : [String] = [] // pubKeys
    var messages : [String : [Message]] = [:] // pubKey -> [message]
    var aliases : [String : String] = [:] // pubKey -> alias string
    
    var currentChatPubKey : String?
    
    required init?(coder aDecoder: NSCoder) {
        self.networkingLayer = NetworkProtocol.sharedInstance
        super.init(coder: aDecoder)
    }
    
    override init(nibName nibNameOrNil: String!, bundle nibBundleOrNil: NSBundle!) {
        self.networkingLayer = NetworkProtocol.sharedInstance
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
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
        
        self.networkingLayer.delegate = self
        
        fetchMessages()
        
        let viewFrame = self.view.frame
        self.messageTable.frame = viewFrame
        self.view.addSubview(messageTable)
        
        self.messageTable.registerClass(ThreadTableViewCell.classForCoder(), forCellReuseIdentifier: "MessageCell")
        self.messageTable.dataSource = self
        self.messageTable.delegate = self
        
        self.title = "🐴"
        let leftButton = UIBarButtonItem(barButtonSystemItem: .Add, target: self, action: #selector(addNewContact))
        self.navigationController?.topViewController?.navigationItem.leftBarButtonItem = leftButton
        let rightButton = UIBarButtonItem(barButtonSystemItem: .Compose, target: self, action: #selector(composeNewMessage))
        self.navigationController?.topViewController?.navigationItem.leftBarButtonItem = rightButton
        
        chatController.delegate = self
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func addNewContact() {
        let alertController = UIAlertController(title: "Add New Name", message: "", preferredStyle: UIAlertControllerStyle.Alert)
        
        let saveAction = UIAlertAction(title: "Save", style: .Default, handler: {
            alert -> Void in
            
            let alias = (alertController.textFields![0] as UITextField).text as String!
            let pubKey = (alertController.textFields![1] as UITextField).text as String!
            
            if((self.aliases[pubKey]) != nil) {
                self.contacts.append(pubKey)
                self.aliases[pubKey] = alias!
                self.messages[pubKey!] = []
            } else {
                print("Already have alias for \(pubKey)")
            }
        })
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .Default, handler: {
            (action : UIAlertAction!) -> Void in
            
        })
        
        alertController.addTextFieldWithConfigurationHandler { (textField : UITextField!) -> Void in
            textField.placeholder = "Alias"
        }
        alertController.addTextFieldWithConfigurationHandler { (textField : UITextField!) -> Void in
            textField.placeholder = "Public Key"
        }
        
        alertController.addAction(saveAction)
        alertController.addAction(cancelAction)
        
        self.presentViewController(alertController, animated: true, completion: nil)
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
        
        self.messageTable.reloadData()
    }
    
    func getEarliestMessageForPublicKey(publicKey : String) -> Message? {
        return (self.messages[publicKey])?.first
    }
    
    func showChatForCurrentPubKey() {
        print("Pushing Chat controller")
        chatController.messages = getMessagesForPublicKey(currentChatPubKey!)
        self.navigationController?.pushViewController(chatController, animated: true)
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
    
    internal func composeNewMessage() {
        let alert = UIAlertController(title: "Choose recipient", message: nil, preferredStyle: .ActionSheet);
        alert.modalInPopover = true;
        
        let pickerFrame: CGRect = CGRectMake(17, 52, 270, 100); // CGRectMake(left), top, width, height) - left and top are like margins
        let picker: UIPickerView = UIPickerView(frame: pickerFrame);
        picker.delegate = self;
        picker.dataSource = self;
        alert.view.addSubview(picker);
        
        self.presentViewController(alert, animated: true, completion: nil)
    }
    
    // MARK: UITableViewDataSource
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("MessageCell", forIndexPath: indexPath) as! ThreadTableViewCell
        
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
        self.messageTable.deselectRowAtIndexPath(indexPath, animated: true)
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
    
    // MARK: UIPickerDelegate
    func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.currentChatPubKey = contacts[row]
        showChatForCurrentPubKey()
    }
    
    // MARK: LGChatControllerDelegate
    func chatController(chatController: LGChatController, didAddNewMessage message: LGChatMessage) {
        print("Added Message: \(message.content)")
    }
    
    func shouldChatController(chatController: LGChatController, addMessage message: LGChatMessage) -> Bool {
        do {
            let actualPubKey = NSData(base64EncodedString: currentChatPubKey!, options: .IgnoreUnknownCharacters)!
            try networkingLayer.sendMessage(message.content.dataUsingEncoding(NSUTF8StringEncoding)!, to: actualPubKey)
        } catch let error as NSError {
            print("Unresolved error \(error), \(error.userInfo)")
            abort()
        }
        
        saveMessage(message.content, from: "Me", withKey: currentChatPubKey!, at: NSDate())
        
        return true
    }
    
    // MARK: NetworkProtocolDelegate
    func receivedMessage(message: NSData?, from publicKey: PublicKey, at time: NSDate) {
        let messageText = String(data: message!, encoding: NSUTF8StringEncoding)!
        let messagePublicKey = String(data: publicKey, encoding: NSUTF8StringEncoding)!
        
        if let previousMessages = self.messages[messagePublicKey] {
            for message in previousMessages {
                let sameTime = message.timestamp.compare(time) == NSComparisonResult.OrderedSame
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

