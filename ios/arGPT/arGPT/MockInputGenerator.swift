//
//  MockInputGenerator.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/12/23.
//

import AVFoundation

class MockInputGenerator {
    private let _voiceSampleFilenames = [
        "Question_CPU",
        "Question_History",
        "Question_Lizards",
        "Question_Movies",
        "Question_Nutrition",
        "Question_Tootsie"
    ]

    private let _queries = [
        "How fast is the CPU in my iPhone?",
        "Did a battle ever happen here in Santa Clara, California?",
        "Where do lizards sleep at night?",
        "Give me three great movie recommendations involving augmented reality.",
        "What is the nutritional content of a Cadbury creme egg?",
        "How many licks does it take to get to the tootsie center of a Tootsie Pop?"
    ]

    public func randomVoiceSample() -> AVAudioPCMBuffer? {
        let filename = _voiceSampleFilenames[Int.random(in: 0..<_voiceSampleFilenames.count)]
        let url = Bundle.main.url(forResource: filename, withExtension: "wav")!
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            print("[MockInputGenerator] Error: Failed to read audio file: \(url.absoluteString)")
            return nil
        }
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
            print("[MockInputGenerator] Error: Failed to create PCM buffer to hold \(frameCount) frames in format: \(audioFile.processingFormat.description)")
            return nil
        }
        do {
            try audioFile.read(into: audioBuffer)
            return audioBuffer
        } catch {
            print("[MockInputGenerator] Error: Failed to read audio file into PCM buffer: \(url.absoluteString)")
            return nil
        }
    }

    public func loadRandomVoiceFile() -> Data? {
        let filename = _voiceSampleFilenames[Int.random(in: 0..<_voiceSampleFilenames.count)]
        let url = Bundle.main.url(forResource: filename, withExtension: "wav")!
        let data = try? Data(contentsOf: url)
        return data
    }

    public func randomQuery() -> String {
        return _queries[Int.random(in: 0..<_queries.count)]
    }
}
