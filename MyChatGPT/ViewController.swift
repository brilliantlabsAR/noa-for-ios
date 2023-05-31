//
//  ViewController.swift
//  MyChatGPT
//
//  Created by Techno Exponent on 11/04/23.
//

import CoreBluetooth
import SwiftyGif
import SwiftUI
import UIKit

class BTNameListing: UITableViewCell {
    @IBOutlet var lblBtName: UILabel!
}

enum BlePeripheral {
    static var connectedPeripheral: CBPeripheral?
    static var connectedService: CBService?
    static var connectedTXChar: CBCharacteristic?
    static var connectedRXChar: CBCharacteristic?
}

enum CBUUIDs {
    static let kBLEService_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
    static let kBLE_Characteristic_uuid_Tx = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
    static let kBLE_Characteristic_uuid_Rx = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

    static let MaxCharacters = 20

    static let BLEService_UUID = CBUUID(string: kBLEService_UUID)
    static let BLE_Characteristic_uuid_Tx = CBUUID(string: kBLE_Characteristic_uuid_Tx) // (Property = Write without response)
    static let BLE_Characteristic_uuid_Rx = CBUUID(string: kBLE_Characteristic_uuid_Rx) // (Property = Read/Notify)
}

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {
    @IBOutlet var lblNoOfDeveice: UILabel!
    @IBOutlet var tableviewChat: UITableView!
    @IBOutlet var imgBT: UIButton!
    @IBOutlet var lblConnected: UILabel!
    @IBOutlet var imgGif: UIImageView!

    private var centralManager: CBCentralManager!
    private var bluefruitPeripheral: CBPeripheral!
    private var txCharacteristic: CBCharacteristic!
    private var rxCharacteristic: CBCharacteristic!
    private var peripheralArray: [CBPeripheral] = []
    private var rssiArray = [NSNumber]()
    private var timer = Timer()
    var Myservices: CBService!

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.isNavigationBarHidden = true
        imgGif.layer.cornerRadius = 44
        imgGif.layer.masksToBounds = false
        imgGif.layer.borderWidth = 1.0
        imgGif.layer.borderColor = UIColor.lightGray.cgColor

        tableviewChat.delegate = self
        tableviewChat.dataSource = self
        tableviewChat.reloadData()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        do {
            let gif = try UIImage(gifName: "bluetooth2", levelOfIntegrity:0.5)
            imgGif.setGifImage(gif, loopCount: -1)
        } catch {
            print(error)
        }
        
      // imgGif.image = UIImage.gif(name: "bluetooth2")
        // Do any additional setup after loading the view.
    }

    override func viewDidAppear(_ animated: Bool) {
        navigationController?.isNavigationBarHidden = true
        disconnectFromDevice()
        tableviewChat.reloadData()
        // startScanning()
    }

    func connectToDevice() {
        centralManager?.connect(bluefruitPeripheral!, options: nil)
    }

    func disconnectFromDevice() {
        if bluefruitPeripheral != nil {
            centralManager?.cancelPeripheralConnection(bluefruitPeripheral!)
        }
    }

    func removeArrayData() {
        centralManager.cancelPeripheralConnection(bluefruitPeripheral)
        rssiArray.removeAll()
        peripheralArray.removeAll()
    }

    func startScanning() {
        // Remove prior data
        peripheralArray.removeAll()
        rssiArray.removeAll()
        // Start Scanning
        centralManager?.scanForPeripherals(withServices: [CBUUIDs.BLEService_UUID])
        print(CBUUIDs.BLEService_UUID)
        lblConnected.text = "Scanning..."
        imgBT.isEnabled = false
        imgGif.isHidden = false
        imgBT.setTitle("", for: .normal)
        imgBT.isHidden = true
        Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
            self.stopScanning()
        }
    }

    func scanForBLEDevices() {
        // Remove prior data
        peripheralArray.removeAll()
        rssiArray.removeAll()
        // Start Scanning
        centralManager?.scanForPeripherals(withServices: [], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        lblConnected.text = "Scanning..."

        Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
            self.stopScanning()
        }
    }

    func stopTimer() {
        // Stops Timer
        timer.invalidate()
    }

    func stopScanning() {
        lblConnected.text = ""
        imgBT.isEnabled = true
        imgGif.isHidden = true
        imgBT.setTitle("Scan", for: .normal)
        imgBT.isHidden = false
        centralManager?.stopScan()
    }

    func delayedConnection() {
        BlePeripheral.connectedPeripheral = bluefruitPeripheral

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Once connected, move to new view controller to manager incoming and outgoing data
            let storyboard = UIStoryboard(name: "Main", bundle: nil)

            let detailViewController = storyboard.instantiateViewController(withIdentifier: "ChatDetailsViewController") as! ChatDetailsViewController

            self.navigationController?.pushViewController(detailViewController, animated: true)
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return peripheralArray.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BTNameListing", for: indexPath) as! BTNameListing

        let peripheralFound = peripheralArray[indexPath.row]

        let rssiFound = rssiArray[indexPath.row]

        if peripheralFound == nil {
            cell.lblBtName.text = "Unknown"
        } else {
            cell.lblBtName.text = peripheralFound.name! + " : \(rssiFound)"
            // cell.rssiLabel.text = "RSSI: \(rssiFound)"
        }
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        bluefruitPeripheral = peripheralArray[indexPath.row]

        BlePeripheral.connectedPeripheral = bluefruitPeripheral

        connectToDevice()
    }

    @IBAction func btnBTScan(_ sender: Any) {
        startScanning()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
            case .poweredOff:
                print("Is Powered Off.")

                let alertVC = UIAlertController(title: "Bluetooth is off", message: "Please turn on your bluetooth", preferredStyle: UIAlertController.Style.alert)

                let action = UIAlertAction(title: "Go to settings", style: UIAlertAction.Style.default, handler: { (_: UIAlertAction) in
                    self.openBluetooth()
                    self.dismiss(animated: true, completion: nil)
                })

                alertVC.addAction(action)

                present(alertVC, animated: true, completion: nil)

            case .poweredOn:

                print("Is Powered On.")

                startScanning()
            case .unsupported:
                print("Is Unsupported.")
            case .unauthorized:
                print("Is Unauthorized.")
            case .unknown:
                print("Unknown")
            case .resetting:
                print("Resetting")
            @unknown default:
                print("Error")
        }
    }

    func openBluetooth() {
        let url = URL(string: "App-Prefs:root=Bluetooth") // for bluetooth setting
        let app = UIApplication.shared
        app.openURL(url!)
    }

    // MARK: - Discover

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        print("Function: \(#function),Line: \(#line)")

        bluefruitPeripheral = peripheral

        if peripheralArray.contains(peripheral) {
            print("Duplicate Found.")
        } else {
            peripheralArray.append(peripheral)
            rssiArray.append(RSSI)
        }

        lblNoOfDeveice.text = " : \(peripheralArray.count)"
        bluefruitPeripheral.delegate = self

        print("Peripheral Discovered: \(peripheral)")

        tableviewChat.reloadData()
    }

    // MARK: - Connect

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        stopScanning()
        bluefruitPeripheral.discoverServices([CBUUIDs.BLEService_UUID])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        BlePeripheral.connectedService = services[0]
        Myservices = services[0]
        sendData()
    }

    func sendData() {
        let RXCharacteristic = Myservices.characteristics?[0].uuid
        // let TXCharacteristic

        print(RXCharacteristic)
    }

//    func sendInitialCommand() {
//        let cmdBytes: [UInt8] = [0x55, 0xe1, 0x00, 0x0a]
//        let cmd = Data(cmdBytes)
//        bluefruitPeripheral!.writeValue(cmd, for: txCharacteristic!, type: .withoutResponse)
//    }
//
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
//        let rxCharacteristicUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
//        let txCharacteristicUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
//        for characteristic in service.characteristics! {
//            if characteristic.uuid == rxCharacteristicUUID {
//                rxCharacteristic = characteristic
//                peripheral.setNotifyValue(true, for: rxCharacteristic!)
//            } else if (characteristic.uuid == txCharacteristicUUID) {
//                txCharacteristic = characteristic
//            }
//        }
//        //sendInitialCommand()
//        delayedConnection()
//    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            return
        }

        print("Found \(characteristics.count) characteristics.")

        for characteristic in characteristics {
            if characteristic.uuid.isEqual(CBUUIDs.BLE_Characteristic_uuid_Rx) {
                rxCharacteristic = characteristic

                BlePeripheral.connectedRXChar = rxCharacteristic

                peripheral.setNotifyValue(true, for: rxCharacteristic!)
                peripheral.readValue(for: characteristic)

                print("RX Characteristic: \(rxCharacteristic.uuid)")
            }

            if characteristic.uuid.isEqual(CBUUIDs.BLE_Characteristic_uuid_Tx) {
                txCharacteristic = characteristic
                BlePeripheral.connectedTXChar = txCharacteristic
                print("TX Characteristic: \(txCharacteristic.uuid)")
            }
        }

        delayedConnection()
    }

    @IBAction func btnTest(_ sender: Any) {}

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        var characteristicASCIIValue = NSString()
        guard characteristic == rxCharacteristic,

              let characteristicValue = characteristic.value,
              let ASCIIstring = NSString(data: characteristicValue, encoding: String.Encoding.utf8.rawValue) else { return }

        characteristicASCIIValue = ASCIIstring

        print("Value Recieved: \(characteristicASCIIValue as String)")
        print(characteristic)
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "Notify"), object: "\(characteristicASCIIValue as String)")
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        peripheral.readRSSI()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("Error discovering services: error")
            return
        }
        print("Function: \(#function),Line: \(#line)")
        print("Message sent")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        print("*******************************************************")
        print("Function: \(#function),Line: \(#line)")
        if error != nil {
            print("Error changing notification state:\(String(describing: error?.localizedDescription))")

        } else {
            print("Characteristic's value subscribed")
        }

        if characteristic.isNotifying {
            print("Subscribed. Notification has begun for: \(characteristic.uuid)")
        }
    }
}
