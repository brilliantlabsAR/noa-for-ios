//
//  SettingsView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/8/23.
//

import SwiftUI

struct SettingsView: View {
    // Our data model
    @EnvironmentObject private var _settings: Settings

    // We cannot publish directly onto the data model because it triggers rendering in the first place, so we need
    // local copies that we manually sync in onAppear and onChange
    @State private var _apiKey: String = ""
    @State private var _model: String = ""
    @State private var _pairedDeviceID: UUID?

    // Observe Monocle devices
    @Binding private var _discoveredDevices: [UUID]

//    private var _fakeDevices: [UUID] = {
//        var devices: [UUID] = []
//        let numDevices = 10
//        for i in 0..<numDevices {
//            devices.append(UUID())
//        }
//        return devices
//    }()

    // Monocle connection state
    @Binding private var _isMonocleConnected: Bool

    // Dismiss ourselves
    @Environment(\.dismiss) private var _dismiss

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    // OpenAI API section
                    Section(header: Text("OpenAI API")) {
                        if _apiKey.isEmpty {
                            Text("An OpenAI API key is required. Sign into your [OpenAI developer account](http://platform.openai.com) and enter your key below.")
                        }

                        LabeledContent {
                            TextField("API Key", text: $_apiKey)
                                .autocorrectionDisabled()
                        } label: {
                            Label("", systemImage: "key.icloud")
                        }

                        LabeledContent {
                            Picker("Model", selection: $_model) {
                                ForEach(_settings.supportedModels, id: \.self) {
                                    Text(_settings.printableModelName(model: $0))
                                }
                            }.pickerStyle(.menu)
                        } label: {
                            Label("", systemImage: "brain.head.profile")
                        }
                    }

                    // Device section
                    Section(header: Text("Monocle")) {

                        if _pairedDeviceID == nil && !_isMonocleConnected {
                            // No device paired or connected
                            Text("Select a nearby Monocle device to pair with.")
                        }

                        // Always display connection status
                        LabeledContent {
                            Text(_isMonocleConnected ? "Connected" : "Not connected")
                        } label: {
                            Label("Status", systemImage: "dot.radiowaves.up.forward")
                        }

                        if _pairedDeviceID == nil && !_isMonocleConnected {
                            // Need to pick a device to pair to
                            LabeledContent {
                                Picker("", selection: $_pairedDeviceID) {
                                    Text("None").tag(nil as UUID?)
                                    ForEach(_discoveredDevices, id: \.self) { deviceID in
                                        Text("\(deviceID.uuidString)").tag(Optional(deviceID))
                                    }
                                }
                            } label: {
                                Label("Device", systemImage: "eye")
                            }
                        } else if _pairedDeviceID != nil {
                            // Device paired, display UUID
                            LabeledContent {
                                Text("\(_pairedDeviceID?.uuidString ?? "None")")
                            } label: {
                                Label("Device", systemImage: "eye")
                            }
                        }

                        // If a device has been chosen, add ability to forget
                        if _pairedDeviceID != nil || _isMonocleConnected {
                            HStack {
                                Spacer()
                                Button(
                                    role: .destructive,
                                    action: { _pairedDeviceID = nil },
                                    label: { Text("Forget") }
                                )
                                Spacer()
                            }
                        }
                    }

                    // Dumb hack to place a button right below the options area
                    Section(footer:
                        HStack {
                            Spacer()

                            Button(
                                role: .none,
                                action: {
                                    _dismiss()
                                },
                                label: {
                                    Text("Done")
                                }
                            )
                            .buttonStyle(.borderedProminent)

                            Spacer()
                        }
                    ) {
                        EmptyView()
                    }
                }
                .navigationBarTitle(Text("Settings"), displayMode: .inline)
            }
        }
        .onAppear {
            // Load the actual values for our local copy
            _apiKey = _settings.apiKey
            _model = _settings.model
            _pairedDeviceID = _settings.pairedDeviceID
        }
        .onChange(of: _apiKey) {
            // Save to settings. For some reason, this does not trigger the dreaded "publishing changes from within view updates is not allowed" warning, even though we write the published value. Maybe onChange() is not considered part of the update?
            _settings.setAPIKey($0)
        }
        .onChange(of: _settings.apiKey) {
            _apiKey = $0
        }
        .onChange(of: _model) {
            _settings.setModel($0)
        }
        .onChange(of: _settings.model) {
            _model = $0
        }
        .onChange(of: _pairedDeviceID) {
            _settings.setPairedDeviceID($0)
        }
        .onChange(of: _settings.pairedDeviceID) {
            _pairedDeviceID = $0
        }
    }

    public init(discoveredDevices: Binding<[UUID]>, isMonocleConnected: Binding<Bool>) {
        __discoveredDevices = discoveredDevices
        __isMonocleConnected = isMonocleConnected
    }
}

struct SettingsView_Previews: PreviewProvider {
    private static var _fakeDevices: [UUID] = {
        var devices: [UUID] = []
        let numDevices = 100
        for i in 0..<numDevices {
            devices.append(UUID())
        }
        return devices
    }()

    static var previews: some View {
        SettingsView(discoveredDevices: .constant(Self._fakeDevices), isMonocleConnected: .constant(true))
            .environmentObject(Settings())
    }
}
