//
//  ThreadTableViewCell.swift
//  HeeHaw
//
//  Created by Ankush Gupta on 5/9/16.
//  Copyright © 2016 Ankush Gupta. All rights reserved.
//

import Foundation
import UIKit

class ThreadTableViewCell: UITableViewCell {
    var messagePeerLabel = UILabel();
    var messageTextLabel = UILabel();
    
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        messagePeerLabel = UILabel(frame: CGRectMake(30, 10, self.bounds.size.width - 40, 20))
        messagePeerLabel.font = UIFont(name: "HelveticaNeue-Bold", size: 18)
        
        messageTextLabel = UILabel(frame: CGRectMake(30, 20, self.bounds.size.width - 40, 40))
        messageTextLabel.textColor = UIColor.lightGrayColor()
        
        self.accessoryType = UITableViewCellAccessoryType.DisclosureIndicator
        
        self.contentView.addSubview(messagePeerLabel)
        self.contentView.addSubview(messageTextLabel)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}