//
//  Settings.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/8/23.
//
//  Manages settings using UserDefaults or keychain.
//
//
//  Resources
//  ---------
//  - "How To Use Multi Value Title and Value From Settings Bundle"
//    https://stackoverflow.com/questions/16451136/how-to-use-multi-value-title-and-value-from-settings-bundle
//  - "Store accessToken in iOS keychain"
//    https://stackoverflow.com/questions/68209016/store-accesstoken-in-ios-keychain
//

import Combine
import Foundation

class Settings: ObservableObject {
    @Published private(set) var imageStrength: Float = 0
    private let k_imageStrength = "stability_image_strength"

    @Published private(set) var imageGuidance: Int = 0
    private let k_imageGuidance = "stability_guidance"

    @Published private(set) var pairedDeviceID: UUID?
    private let k_pairedDeviceID = "paired_device_id"   // this key should *not* appear in Root.plist (therefore cannot be edited in Settings by user directly; only from app)

    @Published private(set) var debug200pxImageMode: Bool = false
    private let k_debug200pxImageMode = "debug_200px_images"

    @Published private(set) var apiToken: String?

    private let k_serviceIdentifier = "xyz.brilliant.argpt.keys.api_tokens"
    private let k_accountIdentifier = "noa"
    private let _keychainQueue = DispatchQueue(label: "xyz.brilliant.argpt.keys", qos: .default)

    public init() {
        Self.registerDefaults()
        NotificationCenter.default.addObserver(self, selector: #selector(Self.onSettingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        onSettingsChanged()
        if let token = loadAPITokenFromKeychain() {
            apiToken = token
        }
    }

    /// Sets the value of the paired device ID.
    /// - Parameter value: The new value or `nil` for none.
    public func setPairedDeviceID(_ value: UUID?) {
        if pairedDeviceID != value {
            pairedDeviceID = value
            let uuidString = value?.uuidString ?? ""    // use "" for none
            UserDefaults.standard.set(uuidString, forKey: k_pairedDeviceID)
            print("[Settings] Set: \(k_pairedDeviceID) = \(uuidString)")
        }
    }

    /// Sets the Noa API token to use for logging into Brillaint's server automatically.
    /// - Parameter token: The new token or `nil` for none.
    public func setAPIToken(_ token: String?) {
        if apiToken != token {
            apiToken = token

            // Use queue because these operations are slow
            _keychainQueue.async { [weak self] in
                guard let self = self else { return }
                if let token = token {
                    saveAPITokenToKeychain(token)
                } else {
                    deleteAPITokenFromKeychain()
                }
            }
        }
    }

    private static func getRootPListURL() -> URL? {
        guard let settingsBundle = Bundle.main.url(forResource: "Settings", withExtension: "bundle") else {
            print("[Settings] Could not find Settings.bundle")
            return nil
        }
        return settingsBundle.appendingPathComponent("Root.plist")
    }

    /// Sets the default values, if values do not already exist, for all settings from our Root.plist
    private static func registerDefaults() {
        guard let url = getRootPListURL() else {
            return
        }

        guard let settings = NSDictionary(contentsOf: url) else {
            print("[Settings] Couldn't find Root.plist in settings bundle")
            return
        }

        guard let preferences = settings.object(forKey: "PreferenceSpecifiers") as? [[String: AnyObject]] else {
            print("[Settings] Root.plist has an invalid format")
            return
        }

        var defaultsToRegister = [String: AnyObject]()
        for preference in preferences {
            if let key = preference["Key"] as? String,
               let value = preference["DefaultValue"] {
                print("[Settings] Registering default: \(key) = \(value.debugDescription ?? "<none>")")
                defaultsToRegister[key] = value as AnyObject
            }
        }

        UserDefaults.standard.register(defaults: defaultsToRegister)
    }

    /// Reads Root.plist to find all possible title and values of a multi-valued item, where the values are strings.
    /// - Parameter withKey: The key of the setting (stored in the "Identifier" field under the multi-value item in Root.plist).
    /// - Returns: Titles and values, or empty for both if an error occurred and the multi-valued item was unable to be read.
    private static func getPossibleTitlesAndValuesForMultiValueItem(withKey key: String) -> ([String], [String]) {
        guard let url = getRootPListURL() else {
            return ([], [])
        }

        guard let data = try? Data(contentsOf: url) else {
            print("[Settings] Unable to load Root.plist")
            return ([], [])
        }

        guard let settings = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(), format: nil) as? [String: Any],
              let preferenceSpecifiers = settings["PreferenceSpecifiers"] as? [[String: Any]] else {
            print("[Settings] Unable to access preference specifiers")
            return ([], [])
        }

        guard let multiValueItem = preferenceSpecifiers.first(where: { $0["Key"] as? String == key }),
              let possibleValues = multiValueItem["Values"] as? [Any],
              let titles = multiValueItem["Titles"] as? [Any] else {
            print("[Settings] Unable to read allowable values for key: \(key)")
            return ([], [])
        }

        return (titles.compactMap { $0 as? String}, possibleValues.compactMap { $0 as? String })
    }

    @objc private func onSettingsChanged() {
        // Publish changes when settings have been edited
        let imageStrength = UserDefaults.standard.float(forKey: k_imageStrength)
        if imageStrength != self.imageStrength {
            self.imageStrength = imageStrength
        }

        let imageGuidance = UserDefaults.standard.integer(forKey: k_imageGuidance)
        if imageGuidance != self.imageGuidance {
            self.imageGuidance = imageGuidance
        }

        let debug200pxImageMode = UserDefaults.standard.bool(forKey: k_debug200pxImageMode)
        if debug200pxImageMode != self.debug200pxImageMode {
            self.debug200pxImageMode = debug200pxImageMode
        }

        // The following properties are not exposed to users in Settings and so may be absent
        var uuid: UUID?
        if let pairedDeviceIDString = UserDefaults.standard.string(forKey: k_pairedDeviceID) {
            uuid = UUID(uuidString: pairedDeviceIDString)   // will be nil if invalid
        }
        if self.pairedDeviceID != uuid {
            self.pairedDeviceID = uuid
        }
    }

    private func loadAPITokenFromKeychain() -> String? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: k_serviceIdentifier,
            kSecAttrAccount: k_accountIdentifier,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        if status != errSecSuccess {
            print("[Settings] No API token in keychain")
            return nil
        }

        if let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        } else {
            print("[Settings] Unable to decode token")
        }

        return nil
    }

    private func deleteAPITokenFromKeychain() {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: k_serviceIdentifier,
            kSecAttrAccount: k_accountIdentifier
        ] as CFDictionary

        let status = SecItemDelete(query)
        if status != errSecSuccess {
            print("[Settings] Unable to delete token: \(status)")
        }
    }

    private func saveAPITokenToKeychain(_ token: String) {
        let attributes = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: k_serviceIdentifier,
            kSecAttrAccount: k_accountIdentifier,
            kSecValueData: token.data(using: .utf8)!,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly    // so we can access this in background mode (but on reset requires unlock)
        ] as CFDictionary

        let status = SecItemAdd(attributes, nil)
        if status != errSecSuccess {
            if status == errSecDuplicateItem {
                updateAPITokenInKeychain(token)
            } else {
                print("[Settings] Unable to save API token: \(status.description)")
            }
        } else {
            print("[Settings] Saved API token")
        }
    }

    private func updateAPITokenInKeychain(_ token: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: k_serviceIdentifier,
            kSecAttrAccount: k_accountIdentifier
        ] as CFDictionary

        let attributes = [
            kSecValueData: token.data(using: .utf8)!
        ] as CFDictionary

        let status = SecItemUpdate(query, attributes)
        if status != errSecSuccess {
            print("[Settings] Unable to update API token: \(status.description)")
        } else {
            print("[Settings] Updated existing API token")
        }
    }
}
