import AVFoundation
import Foundation

struct AudioTrimResult: Sendable {
    let originalDuration: Double
    let outputDuration: Double
    let didTrim: Bool

    var removedDuration: Double {
        max(0, originalDuration - outputDuration)
    }
}

enum AudioSilenceTrimmer {
    private static let chunkFrames: AVAudioFrameCount = 8_192

    static func trim(
        url: URL,
        thresholdDB: Double = -50,
        preRollSeconds: Double,
        postRollSeconds: Double
    ) throws -> AudioTrimResult {
        let inputFile = try AVAudioFile(forReading: url)
        let format = inputFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = inputFile.length

        guard totalFrames > 0, sampleRate > 0 else {
            return AudioTrimResult(originalDuration: 0, outputDuration: 0, didTrim: false)
        }

        let originalDuration = Double(totalFrames) / sampleRate
        let threshold = Float(pow(10, thresholdDB / 20))

        guard let firstSoundFrame = try findFirstSoundFrame(
            in: inputFile,
            format: format,
            totalFrames: totalFrames,
            threshold: threshold
        ), let lastSoundFrame = try findLastSoundFrame(
            in: inputFile,
            format: format,
            totalFrames: totalFrames,
            threshold: threshold
        ) else {
            return AudioTrimResult(
                originalDuration: originalDuration,
                outputDuration: originalDuration,
                didTrim: false
            )
        }

        let preRollFrames = AVAudioFramePosition((max(0, preRollSeconds) * sampleRate).rounded())
        let postRollFrames = AVAudioFramePosition((max(0, postRollSeconds) * sampleRate).rounded())
        let startFrame = max(0, firstSoundFrame - preRollFrames)
        let endFrame = min(totalFrames, lastSoundFrame + 1 + postRollFrames)

        guard startFrame > 0 || endFrame < totalFrames else {
            return AudioTrimResult(
                originalDuration: originalDuration,
                outputDuration: originalDuration,
                didTrim: false
            )
        }

        let outputFrames = max(0, endFrame - startFrame)
        guard outputFrames > 0 else {
            return AudioTrimResult(
                originalDuration: originalDuration,
                outputDuration: originalDuration,
                didTrim: false
            )
        }

        let tempURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.deletingPathExtension().lastPathComponent)-trim-\(UUID().uuidString).wav"
        )

        do {
            var outputFile: AVAudioFile? = try AVAudioFile(forWriting: tempURL, settings: format.settings)
            inputFile.framePosition = startFrame

            var remainingFrames = outputFrames
            while remainingFrames > 0 {
                let count = AVAudioFrameCount(min(AVAudioFramePosition(chunkFrames), remainingFrames))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                    throw AudioTrimError.invalidAudioFormat
                }

                try inputFile.read(into: buffer, frameCount: count)
                guard buffer.frameLength > 0 else { break }
                try outputFile?.write(from: buffer)
                remainingFrames -= AVAudioFramePosition(buffer.frameLength)
            }

            outputFile = nil
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        return AudioTrimResult(
            originalDuration: originalDuration,
            outputDuration: Double(outputFrames) / sampleRate,
            didTrim: true
        )
    }

    private static func findFirstSoundFrame(
        in file: AVAudioFile,
        format: AVAudioFormat,
        totalFrames: AVAudioFramePosition,
        threshold: Float
    ) throws -> AVAudioFramePosition? {
        var position: AVAudioFramePosition = 0
        file.framePosition = 0

        while position < totalFrames {
            let count = AVAudioFrameCount(min(AVAudioFramePosition(chunkFrames), totalFrames - position))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                throw AudioTrimError.invalidAudioFormat
            }

            try file.read(into: buffer, frameCount: count)
            guard buffer.frameLength > 0 else { break }

            if peakMagnitude(in: buffer) >= threshold,
               let localFrame = firstFrameAboveThreshold(in: buffer, threshold: threshold) {
                return position + AVAudioFramePosition(localFrame)
            }

            position += AVAudioFramePosition(buffer.frameLength)
        }

        return nil
    }

    private static func findLastSoundFrame(
        in file: AVAudioFile,
        format: AVAudioFormat,
        totalFrames: AVAudioFramePosition,
        threshold: Float
    ) throws -> AVAudioFramePosition? {
        var endFrame = totalFrames

        while endFrame > 0 {
            let startFrame = max(0, endFrame - AVAudioFramePosition(chunkFrames))
            let count = AVAudioFrameCount(endFrame - startFrame)
            file.framePosition = startFrame

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                throw AudioTrimError.invalidAudioFormat
            }

            try file.read(into: buffer, frameCount: count)
            guard buffer.frameLength > 0 else {
                endFrame = startFrame
                continue
            }

            if peakMagnitude(in: buffer) >= threshold,
               let localFrame = lastFrameAboveThreshold(in: buffer, threshold: threshold) {
                return startFrame + AVAudioFramePosition(localFrame)
            }

            endFrame = startFrame
        }

        return nil
    }

    private static func peakMagnitude(in buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var peak: Float = 0

        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameCount {
                peak = max(peak, abs(samples[frame]))
            }
        }
        return peak
    }

    private static func firstFrameAboveThreshold(
        in buffer: AVAudioPCMBuffer,
        threshold: Float
    ) -> Int? {
        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            for channel in 0..<channelCount where abs(channels[channel][frame]) >= threshold {
                return frame
            }
        }
        return nil
    }

    private static func lastFrameAboveThreshold(
        in buffer: AVAudioPCMBuffer,
        threshold: Float
    ) -> Int? {
        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)

        guard frameCount > 0 else { return nil }
        for frame in stride(from: frameCount - 1, through: 0, by: -1) {
            for channel in 0..<channelCount where abs(channels[channel][frame]) >= threshold {
                return frame
            }
        }
        return nil
    }
}

private enum AudioTrimError: LocalizedError {
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .invalidAudioFormat:
            return "自動トリミング用の音声形式を読み取れませんでした。"
        }
    }
}
