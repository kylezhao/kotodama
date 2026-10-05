//
//  BufferConverter.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import AVFAudio
import Foundation

/// Converts PCM buffers to the format a speech module asks for, reusing one `AVAudioConverter`.
struct BufferConverter {
    enum ConversionError: Error {
        case converterUnavailable
        case bufferAllocationFailed
        case conversionFailed(String)
    }

    private var converter: AVAudioConverter?

    mutating func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard buffer.format != format else { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { throw ConversionError.converterUnavailable }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(max(1, (Double(buffer.frameLength) * ratio).rounded(.up)))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw ConversionError.bufferAllocationFailed
        }

        let consumed = ConsumedFlag()
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed.value {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed.value = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            throw ConversionError.conversionFailed(conversionError?.localizedDescription ?? "unknown")
        }
        return output
    }

    /// The converter's input block is invoked synchronously, so a plain box is enough here.
    private final class ConsumedFlag: @unchecked Sendable {
        var value = false
    }
}

extension AVAudioPCMBuffer {
    /// Deep copy, so a buffer handed out by an audio tap can outlive the callback.
    func cloned() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        copy.frameLength = frameLength
        let channels = Int(format.channelCount)
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        if let source = floatChannelData, let target = copy.floatChannelData {
            for channel in 0..<channels {
                target[channel].update(from: source[channel], count: Int(frameLength))
            }
        } else if let source = int16ChannelData, let target = copy.int16ChannelData {
            for channel in 0..<channels {
                target[channel].update(from: source[channel], count: Int(frameLength))
            }
        } else if let source = int32ChannelData, let target = copy.int32ChannelData {
            for channel in 0..<channels {
                target[channel].update(from: source[channel], count: Int(frameLength))
            }
        } else if bytesPerFrame > 0 {
            memcpy(copy.mutableAudioBufferList.pointee.mBuffers.mData, audioBufferList.pointee.mBuffers.mData, Int(frameLength) * bytesPerFrame)
        }
        return copy
    }

    /// Root-mean-square level normalised to 0...1 for meters.
    var rmsLevel: Float {
        guard let data = floatChannelData, frameLength > 0 else { return 0 }
        let count = Int(frameLength)
        var sum: Float = 0
        for index in 0..<count {
            let sample = data[0][index]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        // Map roughly -50 dB...0 dB onto 0...1.
        let decibels = 20 * log10(max(rms, 1e-6))
        return min(1, max(0, (decibels + 50) / 50))
    }
}
