//
//  Settings.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/8/23.
//
//  Resources
//  ---------
//  - "How To Use Multi Value Title and Value From Settings Bundle"
//    https://stackoverflow.com/questions/16451136/how-to-use-multi-value-title-and-value-from-settings-bundle
//

import Combine
import Foundation

class Settings: ObservableObject {
    @Published private(set) var openAIKey: String = ""
    private static let k_openAIKey = "api_key"

    @Published private(set) var gptModel: String = ""
    private static let k_gptModel = "model"

    @Published private(set) var stabilityAIKey: String = ""
    private static let k_stabilityAIKey = "stability_api_key"

    @Published private(set) var stableDiffusionModel: String = ""
    private static let k_stableDiffusionModelKey = "stability_sd_model"

    @Published private(set) var imageStrength: Float = 0
    private static let k_imageStrength = "stability_image_strength"

    @Published private(set) var imageGuidance: Int = 0
    private static let k_imageGuidance = "stability_guidance"

    @Published private(set) var pairedDeviceID: UUID?
    private static let k_pairedDeviceID = "paired_device_id"    // this key should *not* appear in Root.plist (therefore cannot be edited in Settings by user directly; only from app)

    public let supportedGPTModels: [String]

    private let _gptModelToPrintableName: [String: String]

    public init() {
        Self.registerDefaults()

        let (modelNames, supportedModels) = Self.getPossibleTitlesAndValuesForMultiValueItem(withKey: Self.k_gptModel)
        self.supportedGPTModels = supportedModels

        var modelToPrintableName: [String: String] = [:]
        for i in 0..<min(modelNames.count, supportedModels.count) {
            modelToPrintableName[supportedModels[i]] = modelNames[i]
        }
        _gptModelToPrintableName = modelToPrintableName

        NotificationCenter.default.addObserver(self, selector: #selector(Self.onSettingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        onSettingsChanged()
    }

    public func printableGPTModelName(model: String) -> String {
        guard let name = _gptModelToPrintableName[model] else {
            return "?"
        }
        return name
    }

    /// Sets the value of the OpenAI API key setting and persists it.
    /// - Parameter value: The new value.
    public func setOpenAIKey(_ value: String) {
        if openAIKey != value {
            openAIKey = value
            UserDefaults.standard.set(value, forKey: Self.k_openAIKey)
            print("[Settings] Set: \(Self.k_openAIKey) = \(openAIKey)")
        }
    }

    /// Sets the value of the Stability AI API key setting and persists it.
    /// - Parameter value: The new value.
    public func setStabilityAIKey(_ value: String) {
        if stabilityAIKey != value {
            stabilityAIKey = value
            UserDefaults.standard.set(value, forKey: Self.k_stabilityAIKey)
            print("[Settings] Set: \(Self.k_stabilityAIKey) = \(stabilityAIKey)")
        }
    }

    /// Sets the value of the model setting. Currently does not perform validation to ensure an allowed value is used.
    /// - Parameter value: The new value.
    public func setGPTModel(_ value: String) {
        if gptModel != value {
            gptModel = value
            UserDefaults.standard.set(value, forKey: Self.k_gptModel)
            print("[Settings] Set: \(Self.k_gptModel) = \(gptModel)")
        }
    }

    /// Sets the value of the paired device ID.
    /// - Parameter value: The new value or `nil` for none.
    public func setPairedDeviceID(_ value: UUID?) {
        if pairedDeviceID != value {
            pairedDeviceID = value
            let uuidString = value?.uuidString ?? ""    // use "" for none
            UserDefaults.standard.set(uuidString, forKey: Self.k_pairedDeviceID)
            print("[Settings] Set: \(Self.k_pairedDeviceID) = \(uuidString)")
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

        guard let settings = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
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
        let openAIKey = UserDefaults.standard.string(forKey: Self.k_openAIKey) ?? ""
        if openAIKey != self.openAIKey {
            self.openAIKey = openAIKey
        }

        let model = UserDefaults.standard.string(forKey: Self.k_gptModel) ?? "gpt-3.5-turbo"
        if model != self.gptModel {
            self.gptModel = model
        }

        let stabilityAIKey = UserDefaults.standard.string(forKey: Self.k_stabilityAIKey) ?? ""
        if stabilityAIKey != self.stabilityAIKey {
            self.stabilityAIKey = stabilityAIKey
        }

        let stableDiffusionModel = UserDefaults.standard.string(forKey: Self.k_stableDiffusionModelKey) ?? ""
        if stableDiffusionModel != self.stableDiffusionModel {
            self.stableDiffusionModel = stableDiffusionModel
        }

        let imageStrength = UserDefaults.standard.float(forKey: Self.k_imageStrength)
        if imageStrength != self.imageStrength {
            self.imageStrength = imageStrength
        }

        let imageGuidance = UserDefaults.standard.integer(forKey: Self.k_imageGuidance)
        if imageGuidance != self.imageGuidance {
            self.imageGuidance = imageGuidance
        }

        // This property is not exposed to users in Settings and so may be absent
        var uuid: UUID?
        if let pairedDeviceIDString = UserDefaults.standard.string(forKey: Self.k_pairedDeviceID) {
            uuid = UUID(uuidString: pairedDeviceIDString)   // will be nil if invalid
        }
        if self.pairedDeviceID != uuid {
            self.pairedDeviceID = uuid
        }
    }
}
