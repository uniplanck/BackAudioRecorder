import AVFoundation
import Foundation

enum FixtureError: Error {
    case invalidArguments
    case invalidFormat
    case unexpectedResult(String)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else { throw FixtureError.invalidArguments }

let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
let work = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
let sampleRate = 48_000.0
let totalFrames = 48_000

try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

guard let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: sampleRate,
    channels: 1,
    interleaved: false
) else { throw FixtureError.invalidFormat }

func makeInput(at url: URL, sound: Bool) throws {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
          let channel = buffer.floatChannelData?[0] else { throw FixtureError.invalidFormat }
    buffer.frameLength = AVAudioFrameCount(totalFrames)
    for frame in 0..<totalFrames {
        channel[frame] = sound && (12_000..<36_000).contains(frame) ? 0.5 : 0.0
    }
    var output: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
    try output?.write(from: buffer)
    output = nil
}

func check(_ name: String, preRoll: Double, postRoll: Double, expectedFrames: AVAudioFramePosition, expectedTrim: Bool, sound: Bool) throws {
    let url = work.appendingPathComponent("\(name).wav")
    try makeInput(at: url, sound: sound)
    let result = try AudioSilenceTrimmer.trim(url: url, preRollSeconds: preRoll, postRollSeconds: postRoll)
    let frames = try AVAudioFile(forReading: url).length
    let expectedDuration = Double(expectedFrames) / sampleRate
    guard frames == expectedFrames,
          result.didTrim == expectedTrim,
          abs(result.outputDuration - expectedDuration) < 0.000_001 else {
        throw FixtureError.unexpectedResult("\(name): frames=\(frames), duration=\(result.outputDuration), didTrim=\(result.didTrim)")
    }
}

try check("no-padding", preRoll: 0, postRoll: 0, expectedFrames: 24_000, expectedTrim: true, sound: true)
try check("with-padding", preRoll: 0.1, postRoll: 0.1, expectedFrames: 33_600, expectedTrim: true, sound: true)
try check("all-silence", preRoll: 0, postRoll: 0, expectedFrames: 48_000, expectedTrim: false, sound: false)
print("audio-trim-regression:3/3 PASS")
