//
//  AVAudioPCMBuffer+Extensions.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 5/20/23.
//

import AVFoundation

extension AVAudioPCMBuffer
{
    public static func fromMonoInt16Data(_ data: Data, sampleRate: Int) -> AVAudioPCMBuffer? {
        // Allocate buffer
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame) else {
            return nil
        }

        // Get the underlying memory for the PCM buffer and copy data into it
        guard let destSamples = buffer.int16ChannelData else {
            return nil
        }
        let destPtr = UnsafeMutableBufferPointer(start: destSamples.pointee, count: Int(buffer.frameCapacity))
        destPtr.withMemoryRebound(to: UInt8.self) { destBytes -> Void in
            // Now we have the destination as a byte buffer and can copy from the data buffer
            _ = data.copyBytes(to: destBytes)
        }
        buffer.frameLength = buffer.frameCapacity
        return buffer
    }

    public func convertToCMSampleBuffer(presentationTimeStamp: CMTime? = nil) -> CMSampleBuffer? {
        if self.frameLength == 0 {
            // Procedure below does not work for zero-length buffers
            return nil
        }

        // https://gist.github.com/aibo-cora/c57d1a4125e145e586ecb61ebecff47c
        let pcmBuffer = self
        let audioBufferList = pcmBuffer.mutableAudioBufferList
        let asbd = pcmBuffer.format.streamDescription

        var sampleBuffer: CMSampleBuffer? = nil
        var format: CMFormatDescription? = nil

        var status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )

        if (status != noErr) {
            return nil
        }

        var timing: CMSampleTimingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
            presentationTimeStamp: presentationTimeStamp ?? CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: CMTime.invalid
        )
    
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: CMItemCount(pcmBuffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        if (status != noErr) {
            print("[AVAudioPCMBuffer] CMSampleBufferCreate failed: \(status)")
            return nil
        }

        status = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: audioBufferList
        )

        if (status != noErr) {
            print("[AVAudioPCMBuffer] CMSampleBufferSetDataBufferFromAudioBufferList failed: \(status)")
            return nil
        }

        return sampleBuffer
    }
}
