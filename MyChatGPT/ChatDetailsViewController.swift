//
//  ChatDetailsViewController.swift
//  MyChatGPT
//
//  Created by Techno Exponent on 20/04/23.
//

import UIKit
import CoreBluetooth
import Alamofire
import Combine
import IQKeyboardManagerSwift

class ChatSendCell:UITableViewCell{
    
    @IBOutlet weak var lblTXName: UILabel!
    @IBOutlet weak var lblSendTxt: UILabel!
}
class ChatReceiveCell:UITableViewCell{
    @IBOutlet weak var lblReceiveTxt: UILabel!
    @IBOutlet weak var lblRXName: UILabel!
    
}
//        let rxCharacteristicUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
//        let txCharacteristicUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")

class ChatDetailsViewController: UIViewController,CBPeripheralManagerDelegate,UITableViewDelegate,UITableViewDataSource,UITextFieldDelegate {
    var peripheralManager: CBPeripheralManager?
    var peripheral: CBPeripheral?
    var periperalTXCharacteristic: CBCharacteristic?
    var cancellables = Set<AnyCancellable>()
    
    @IBOutlet weak var tableviewChat: UITableView!
    
    @IBOutlet weak var lblDeviceName: UILabel!
    @IBOutlet weak var txtChat: UITextField!
    var arrSendChat = [String]()
    var arrReceiveChat = [String]()
    var chatMessages: [ChatMessage] = []
    var messageText: String = ""//"Indian PM Name ?"
    let openAIService = OpenAIService()
    //@State var cancellables = Set<AnyCancellable>()
    var listArray = [[String : String]]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.tableviewChat.delegate = self
        self.tableviewChat.dataSource = self
        //self.tableviewChat.reloadData()
        
        txtChat.returnKeyType = UIReturnKeyType.done
        txtChat.keyboardType = .default
        txtChat.autocorrectionType = .no
        txtChat.isSecureTextEntry = false
        txtChat.isEnabled = true
        txtChat.delegate = self
        txtChat.setLeftPaddingPoints(10)
      
        NotificationCenter.default.addObserver(self, selector: #selector(self.appendRxDataToTextView(notification:)), name: NSNotification.Name(rawValue: "Notify"), object: nil)
        
        
        self.navigationController?.isNavigationBarHidden = true
        self.lblDeviceName.text = "Device Name : " + (BlePeripheral.connectedPeripheral?.name)!
        
        // Do any additional setup after loading the view.
    }
    @objc func appendRxDataToTextView(notification: Notification) -> Void{
//        arrReceiveChat.append("\(notification.object!) \n")
        listArray.append(["text": "\(notification.object!)", "type": "recive"])
        self.tableviewChat.reloadData()
        
        let a = "\n[Recv]: \(notification.object!) \n"
        print(a)
      //consoleTextView.text.append("\n[Recv]: \(notification.object!) \n")
        
    }
    func appendTxDataToTextView(){
//        arrSendChat.append("\(String(txtChat.text!)) \n")
        listArray.append(["text": "\(String(txtChat.text!))", "type": "sender"])
        self.tableviewChat.reloadData()
        
        let b = "\n[Sent]: \(String(txtChat.text!)) \n"
        print(b)
    
    }
    
    
    @IBAction func btnBack(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }
    
    @IBAction func btnSend(_ sender: Any) {
        writeOutgoingValue(data: "print(hello)")
//        self.view.endEditing(true)
//        writeOutgoingValue(data: txtChat.text ?? "")
//        appendTxDataToTextView()
        //sendMessage()
    }
    func sendMessage() {
        let myMessage = ChatMessage(id: UUID().uuidString, content: "\(String(txtChat.text!))", dateCreated: Date(), sender: .me)
        chatMessages.append(myMessage)
        openAIService.sendMessage(message: "\(String(txtChat.text!))").sink { completion in
            // Handle errors
        } receiveValue: { response in
            guard let textResponse = response.choices.first?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                return
                
            }
            let gptMessage = ChatMessage(id: response.id, content: textResponse, dateCreated: Date(), sender: .gpt)
            self.chatMessages.append(gptMessage)
            self.listArray.append(["text": textResponse, "type": "recive"])
            self.tableviewChat.reloadData()
            self.txtChat.text = ""
        }
        .store(in: &cancellables)
        txtChat.text = "";
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
        
    //Check when someone subscribe to our characteristic, start sending the data
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
        if "\((self.listArray[indexPath.item])["type"] ?? "")" == "sender" {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ChatSendCell", for: indexPath) as! ChatSendCell

               cell.lblSendTxt.text = "\((self.listArray[indexPath.item])["text"] ?? "")"
               cell.lblTXName.textColor = UIColor.green
              // cell.lblTXName.text = "TX SENDER : \(String(BlePeripheral.connectedTXChar!.uuid.uuidString))"
            //"\(String(UUID().uuidString))"
               cell.selectionStyle = .none
               return cell
        }else{
            let cell = tableView.dequeueReusableCell(withIdentifier: "ChatReceiveCell", for: indexPath) as! ChatReceiveCell
                cell.lblReceiveTxt.text =  "\((self.listArray[indexPath.item])["text"] ?? "")"
                cell.lblRXName.textColor = UIColor.red
                //cell.lblRXName.text = "RX RECEIVER : \(String(BlePeripheral.connectedRXChar!.uuid.uuidString))"
                cell.selectionStyle = .none
                return cell
        }
        
//        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatReceiveCell", for: indexPath) as! ChatReceiveCell
//
//            cell.selectionStyle = .none
//            return cell
        
    }
    // Write functions
    func writeOutgoingValue(data: String){
        let cmdBytes: [UInt8] = [0x55, 0xe1, 0x00, 0x0a]
        let cmd = Data(cmdBytes)
//        let value: UInt8 = 0xDE
//        let data = Data(bytes: [value])
        
//        var parameter = NSInteger(1)
//        let data = NSData(bytes: &parameter, length: 1)
       
       // let valueString = (data as NSString).data(using: String.Encoding.utf8.rawValue)
       //change the "data" to valueString
        
      if let blePeripheral = BlePeripheral.connectedPeripheral {
            if let txCharacteristic = BlePeripheral.connectedTXChar {
               // blePeripheral.writeValue(valueString!, for: txCharacteristic, type: .withoutResponse)
                blePeripheral.writeValue(cmd, for: txCharacteristic, type: .withoutResponse)
                //blePeripheral.writeValue(data, for: txCharacteristic, type: .withResponse)
               // blePeripheral.writeValue(data as Data, for: txCharacteristic, type: .withResponse)
            }
        }
        
//        let blePeripheral = BlePeripheral.connectedPeripheral
//        let txCharacteristic = BlePeripheral.connectedTXChar
//        let cmdBytes: [UInt8] = [0x55, 0xe1, 0x00, 0x0a]
//        let cmd = Data(cmdBytes)
//        blePeripheral!.writeValue(valueString!, for: txCharacteristic!, type: .withoutResponse)
        
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
      writeOutgoingValue(data: txtChat.text ?? "")
      appendTxDataToTextView()
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
    func setLeftPaddingPoints(_ amount:CGFloat){
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: amount, height: self.frame.size.height))
        self.leftView = paddingView
        self.leftViewMode = .always
    }
    func setRightPaddingPoints(_ amount:CGFloat) {
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: amount, height: self.frame.size.height))
        self.rightView = paddingView
        self.rightViewMode = .always
    }
}
