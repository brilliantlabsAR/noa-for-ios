//
//  M4AWriter.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/20/23.
//

import AVFoundation

class M4AWriter: NSObject, AVAssetWriterDelegate {
    private let _temporaryDirectory: URL

    public override init() {
        _temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        super.init()
    }

    deinit {
        //TODO: last file created is not cleaned up and should probably be cleaned up here
    }

    public func write(buffer: AVAudioPCMBuffer, completion: @escaping (Data?) -> Void) {
        guard let cmSampleBuffer = buffer.convertToCMSampleBuffer() else {
            print("[M4AWriter] Error: Unable to convert PCM buffer to CMSampleBuffer")
            completion(nil)
            return
        }

        let file = getFileURL()

        guard let assetWriter = try? AVAssetWriter(outputURL: file, fileType: .m4a) else {
            print("[M4AWriter] Error: Unable to create asset writer")
            completion(nil)
            return
        }

        assetWriter.shouldOptimizeForNetworkUse = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,     // voice transcription models want 16 KHz but AVAssetWriter can only encode 44.1 and 48KHz
            AVNumberOfChannelsKey: 1,   // we want only a single channel
            AVEncoderBitRateKey: 128000
        ]

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)

        assetWriter.add(audioInput)

        if !assetWriter.startWriting() {
            print("[M4AWriter] Error: Unable to start writing: \(assetWriter.error?.localizedDescription ?? "unknown error")")
        }
        assetWriter.startSession(atSourceTime: .zero)
        audioInput.append(cmSampleBuffer)
        audioInput.markAsFinished()
        //assetWriter.endSession(atSourceTime: .zero)   //TODO: seems this is not needed?
        assetWriter.finishWriting {
            if assetWriter.status == .completed {
                print("[M4AWriter] Created m4a file successfully")
                self.load(file: file, completion: completion)
                self.delete(file: file)
            } else if assetWriter.status == .failed {
                print("[M4AWriter] Error: Failed to create m4a file: \(assetWriter.error?.localizedDescription ?? "unknown error") \(assetWriter.status)")
            } else {
                print("[M4AWriter]: Error: Failed to create m4a file")
            }
        }
    }

    private func getFileURL() -> URL {
        return _temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func load(file url: URL, completion: (Data?) -> Void) {
        let data = try? Data(contentsOf: url)
        completion(data)
    }

    private func delete(file url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("[M4AWriter] Error: Unable to delete temporary file: \(url)")
        }
    }
}

