//
//  ChatDetailsViewController.swift
//  MyChatGPT
//
//  Created by Techno Exponent on 20/04/23.
//

import Alamofire
import Combine
import CoreBluetooth
import IQKeyboardManagerSwift
import UIKit

class ChatSendCell: UITableViewCell {
    @IBOutlet var lblSendTxt: UILabel!
    @IBOutlet weak var lblTimeSentText: UILabel!
}

class ChatReceiveCell: UITableViewCell {
    @IBOutlet var lblReceiveTxt: UILabel!
    @IBOutlet weak var lblTimeReceiveText: UILabel!
}

class ChatDetailsViewController: UIViewController, CBPeripheralManagerDelegate, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate {
    var peripheralManager: CBPeripheralManager?
    var peripheral: CBPeripheral?
    var periperalTXCharacteristic: CBCharacteristic?
    var cancellables = Set<AnyCancellable>()
    @IBOutlet var tableviewChat: UITableView!
    
    @IBOutlet var lblDeviceName: UILabel!
    @IBOutlet var txtChat: UITextField!
    var arrSendChat = [String]()
    var arrReceiveChat = [String]()
    var chatMessages: [ChatMessage] = []
    var messageText: String = ""
    let openAIService = OpenAIService()
    var listArray = [[String: String]]()
    var isOpenAI:Bool = true
    var isFastTime = false
    var timer = Timer()
    var array = [String]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableviewChat.delegate = self
        tableviewChat.dataSource = self
        txtChat.returnKeyType = UIReturnKeyType.default
        txtChat.keyboardType = .default
        txtChat.autocorrectionType = .no
        txtChat.isSecureTextEntry = false
        txtChat.isEnabled = true
        txtChat.delegate = self
        txtChat.setLeftPaddingPoints(10)
        self.callOneTimewriteOutgoingValue()
        NotificationCenter.default.addObserver(self, selector: #selector(appendRxDataToTextView(notification:)), name: NSNotification.Name(rawValue: "Notify"), object: nil)
        navigationController?.isNavigationBarHidden = true
        lblDeviceName.text = "Device Name : " + (BlePeripheral.connectedPeripheral?.name)!
        // Do any additional setup after loading the view.
    }
    
    @objc func appendRxDataToTextView(notification: Notification) {
        let a = "\n[Recv]: \(notification.object!) \n"
        print(a)
        if isFastTime == false{
            isFastTime = true
            listArray.append(["text": "\(notification.object!)", "type": "recive" ,"time": chatTime()])
            tableviewChat.reloadData()
            scrollToLastIndex()
            return
        }
        if isOpenAI == true{
            sendGPTMessage(notification: notification)
            isOpenAI = false
        }else{
            isOpenAI = true
            listArray.append(["text": "\(notification.object!)", "type": "recive" ,"time": chatTime()])
            tableviewChat.reloadData()
            scrollToLastIndex()
        }
    }

    func appendTxDataToTextView(String:String) {
        listArray.append(["text": "\(String)", "type": "sender", "time": chatTime()])
        tableviewChat.reloadData()
        scrollToLastIndex()
        
        let b = "\n[Sent]: \(String) \n"
        print(b)
    }
    func chatTime()-> String{
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        let date = formatter.string(from: Date())
        return date
    }
    @IBAction func btnBack(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }
    
    
    @IBAction func btnSend(_ sender: Any) {
        let question = txtChat.text ?? ""
        self.timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true, block: { _ in
            self.appendTxDataToTextView(String: question)
            self.writeOutgoingValue(data: question)
            })
        
    }

    //MARK: - Function to scroll the table to bottom
        @objc func scrollToLastIndex()
        {
            if self.listArray.count > 0
            {
                let indexP = IndexPath(row: (self.listArray.count - 1), section: 0)
                self.tableviewChat.scrollToRow(at: indexP, at: .bottom, animated: false)
            }
        }
    
    func sendGPTMessage(notification:Notification) {
        let myMessage = ChatMessage(id: UUID().uuidString, content: "\(notification.object!)", dateCreated: Date(), sender: .me)
        chatMessages.append(myMessage)
        openAIService.sendMessage(message: "\(notification.object!)").sink { _ in
            // Handle errors
        } receiveValue: { response in
            guard let textResponse = response.choices.first?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                return
            }
            let gptMessage = ChatMessage(id: response.id, content: textResponse, dateCreated: Date(), sender: .gpt)
            self.chatMessages.append(gptMessage)
            self.writeOutgoingValue(data: textResponse)
            self.tableviewChat.reloadData()
            self.txtChat.text = ""
        }
        .store(in: &cancellables)
        txtChat.text = ""
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("Peripheral Is Powered On.")
        case .unsupported:
            print("Peripheral Is Unsupported.")
        case .unauthorized:
            print("Peripheral Is Unauthorized.")
        case .unknown:
            print("Peripheral Unknown")
        case .resetting:
            print("Peripheral Resetting")
        case .poweredOff:
            print("Peripheral Is Powered Off.")
        @unknown default:
            print("Error")
        }
    }
        
    // Check when someone subscribe to our characteristic, start sending the data
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("Device subscribe to characteristic")
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return listArray.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if "\(listArray[indexPath.item]["type"] ?? "")" == "sender" {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ChatSendCell", for: indexPath) as! ChatSendCell
            cell.lblSendTxt.text = "\(listArray[indexPath.item]["text"] ?? "")"
            cell.lblTimeSentText.text = "\(listArray[indexPath.item]["time"] ?? "")"
            cell.selectionStyle = .none
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ChatReceiveCell", for: indexPath) as! ChatReceiveCell
            cell.lblReceiveTxt.text = "\(listArray[indexPath.item]["text"] ?? "")"
            cell.lblTimeReceiveText.text = "\(listArray[indexPath.item]["time"] ?? "")"
            cell.selectionStyle = .none
            return cell
        }
    }

    // Write functions
    func writeOutgoingValue(data: String) {
        let cmdBytes1: [UInt8] = [0x04]
        let cmd1 = Data(cmdBytes1)
        
        var TxNotify: UInt8 = 0001
        let enableBytes = Data(bytes: &TxNotify, count: 8)
    
       //let myStr = "import time\nwhile True:\n    print('\(data)')\n    time.sleep(5)"
        let myStr = "print('\(data)')\n"
        
        let firstNBytes = Data(myStr.utf8)

        if let blePeripheral = BlePeripheral.connectedPeripheral {
            if let txCharacteristic = BlePeripheral.connectedTXChar {
                blePeripheral.writeValue(firstNBytes, for: txCharacteristic, type: .withResponse)
                blePeripheral.writeValue(cmd1, for: txCharacteristic, type: .withResponse)
            }
        }
    }
    
    func callOneTimewriteOutgoingValue() {
        let cmdBytes: [UInt8] = [0x01]
        let cmd = Data(cmdBytes)
        if let blePeripheral = BlePeripheral.connectedPeripheral {
            if let txCharacteristic = BlePeripheral.connectedTXChar {
                blePeripheral.writeValue(cmd, for: txCharacteristic, type: .withResponse)
              
            }
        }
    }
    
    
//    Monocle sends a question over BLE using print("Australia PM name")
//    Phone forwards the question to openAI API
//    Phone receives back response form open AI with answer
//    Phone sends answer to Monocle
//    All of this needs to be tested in background mode
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        txtChat.resignFirstResponder()
        txtChat.text = ""
        return true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        txtChat.clearsOnBeginEditing = true
        return true
    }
}

extension UITextField {
    func setLeftPaddingPoints(_ amount: CGFloat) {
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: amount, height: frame.size.height))
        leftView = paddingView
        leftViewMode = .always
    }

    func setRightPaddingPoints(_ amount: CGFloat) {
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: amount, height: frame.size.height))
        rightView = paddingView
        rightViewMode = .always
    }
}
