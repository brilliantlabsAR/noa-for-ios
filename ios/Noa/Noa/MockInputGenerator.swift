//
//  MockInputGenerator.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/12/23.
//

import AVFoundation

class MockInputGenerator {
    private let _voiceSampleFilenames = [
        "Question_CPU.wav",
        "Question_History.wav",
        "Question_Lizards.wav",
        "Question_Movies.wav",
        "Question_Nutrition.wav",
        "Question_Tootsie.wav"
    ]

    private let _nonEnglishVoiceSampleFilenames = [
        "Statement_Chinese.m4a"
    ]

    private let _queries = [
        "How fast is the CPU in my iPhone?",
        "Did a battle ever happen here in Santa Clara, California?",
        "Where do lizards sleep at night?",
        "Give me three great movie recommendations involving augmented reality.",
        "What is the nutritional content of a Cadbury creme egg?",
        "How many licks does it take to get to the tootsie center of a Tootsie Pop?"
    ]

    public func randomVoiceSample(english: Bool = true) -> AVAudioPCMBuffer? {
        let filenames = english ? _voiceSampleFilenames : _nonEnglishVoiceSampleFilenames
        let filename = filenames[Int.random(in: 0..<filenames.count)]
        let url = Bundle.main.url(forResource: filename, withExtension: nil)!
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

    public func loadRandomVoiceFile(english: Bool = true) -> Data? {
        let filenames = english ? _voiceSampleFilenames : _nonEnglishVoiceSampleFilenames
        let filename = filenames[Int.random(in: 0..<filenames.count)]
        let url = Bundle.main.url(forResource: filename, withExtension: nil)!
        let data = try? Data(contentsOf: url)
        return data
    }

    public func randomQuery() -> String {
        return _queries[Int.random(in: 0..<_queries.count)]
    }
}
