import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class SystemAudioRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case recording
        case stopping
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastSavedURL: URL?
    @Published private(set) var startedAt: Date?
    @Published var errorMessage: String?
    @Published var autoTrimEnabled: Bool = UserDefaults.standard.bool(forKey: "BackAudioRecorder.autoTrimEnabled") {
        didSet { UserDefaults.standard.set(autoTrimEnabled, forKey: "BackAudioRecorder.autoTrimEnabled") }
    }
    @Published var preRollSeconds: Double = UserDefaults.standard.object(forKey: "BackAudioRecorder.preRollSeconds") == nil
        ? 1.0
        : max(0, UserDefaults.standard.double(forKey: "BackAudioRecorder.preRollSeconds")) {
        didSet { UserDefaults.standard.set(preRollSeconds, forKey: "BackAudioRecorder.preRollSeconds") }
    }
    @Published var postRollSeconds: Double = UserDefaults.standard.object(forKey: "BackAudioRecorder.postRollSeconds") == nil
        ? 2.0
        : max(0, UserDefaults.standard.double(forKey: "BackAudioRecorder.postRollSeconds")) {
        didSet { UserDefaults.standard.set(postRollSeconds, forKey: "BackAudioRecorder.postRollSeconds") }
    }
    @Published private(set) var waveformLevels = Array(repeating: 0.0, count: 56)
    @Published private(set) var trimSummary: String?

    private let audioQueue = DispatchQueue(label: "com.uniplanck.BackAudioRecorder.audio", qos: .userInitiated)
    private var stream: SCStream?
    private var writer: AudioSampleBufferWriter?

    var isRecording: Bool { state == .recording }
    var isBusy: Bool { state == .starting || state == .stopping }

    var statusText: String {
        switch state {
        case .idle:
            if lastSavedURL == nil { return "Macのシステム音声だけを録音" }
            return trimSummary == nil ? "WAVを保存しました" : "WAVを保存しました · 自動トリミング済み"
        case .starting:
            return "録音を開始しています…"
        case .recording:
            return "録音中 · マイクは入りません"
        case .stopping:
            return "WAVを保存しています…"
        }
    }

    func toggle() async {
        switch state {
        case .idle:
            await start()
        case .recording:
            await stop()
        case .starting, .stopping:
            break
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func start() async {
        guard state == .idle else { return }

        state = .starting
        errorMessage = nil
        lastSavedURL = nil
        trimSummary = nil
        waveformLevels = Array(repeating: 0.0, count: 56)

        do {
            let outputURL = try makeOutputURL()
            let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = preferredDisplay(from: shareable.displays) else {
                throw RecorderError.noDisplay
            }

            let writer = AudioSampleBufferWriter(outputURL: outputURL) { [weak self] peak in
                Task { @MainActor [weak self] in
                    self?.appendWaveformPeak(peak)
                }
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.queueDepth = 3
            configuration.showsCursor = false
            configuration.capturesAudio = true
            if #available(macOS 15.0, *) {
                configuration.captureMicrophone = false
            }
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2

            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: audioQueue)
            try await stream.startCapture()

            self.writer = writer
            self.stream = stream
            self.startedAt = Date()
            self.state = .recording
        } catch {
            self.stream = nil
            self.writer = nil
            self.startedAt = nil
            self.state = .idle
            self.errorMessage = userFacingMessage(for: error)
        }
    }

    private func stop() async {
        guard state == .recording else { return }

        state = .stopping
        let activeStream = stream
        let activeWriter = writer
        stream = nil
        writer = nil

        var stopError: Error?
        if let activeStream {
            do {
                try await activeStream.stopCapture()
            } catch {
                stopError = error
            }
        }

        do {
            guard let activeWriter else { throw RecorderError.writerUnavailable }
            let savedURL = try activeWriter.finish()
            lastSavedURL = savedURL
            errorMessage = stopError.map { "録音停止時に警告がありましたが、WAVは保存済みです: \($0.localizedDescription)" }

            if autoTrimEnabled {
                let preRoll = preRollSeconds
                let postRoll = postRollSeconds
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try AudioSilenceTrimmer.trim(
                            url: savedURL,
                            preRollSeconds: preRoll,
                            postRollSeconds: postRoll
                        )
                    }.value

                    if result.didTrim {
                        trimSummary = String(
                            format: "前後の無音を %.1f秒カット · Pre %.1f秒 / Post %.1f秒",
                            result.removedDuration,
                            preRoll,
                            postRoll
                        )
                    } else {
                        trimSummary = "トリミング対象の前後無音はありませんでした"
                    }
                } catch {
                    errorMessage = "WAVは保存しましたが、自動トリミングに失敗しました: \(error.localizedDescription)"
                }
            }
        } catch {
            lastSavedURL = nil
            trimSummary = nil
            errorMessage = userFacingMessage(for: error)
        }

        startedAt = nil
        state = .idle
    }

    private func appendWaveformPeak(_ peak: Float) {
        guard state == .starting || state == .recording else { return }
        let safePeak = max(Double(peak), 0.000_001)
        let decibels = 20 * log10(safePeak)
        let normalized = min(1, max(0, (decibels + 60) / 60))
        waveformLevels.append(normalized)
        if waveformLevels.count > 56 {
            waveformLevels.removeFirst(waveformLevels.count - 56)
        }
    }

    private func preferredDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        let mainID = CGMainDisplayID()
        return displays.first(where: { $0.displayID == mainID }) ?? displays.first
    }

    private func makeOutputURL() throws -> URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music", isDirectory: true)
            .appendingPathComponent("BackAudioRecorder", isDirectory: true)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "BackAudio-\(formatter.string(from: Date())).wav"
        return folder.appendingPathComponent(name)
    }

    private func userFacingMessage(for error: Error) -> String {
        if !CGPreflightScreenCaptureAccess() {
            return "初回のみ「画面とシステムオーディオ録音」の許可が必要です。許可後にアプリを開き直してください。"
        }
        return error.localizedDescription
    }
}

private enum RecorderError: LocalizedError {
    case noDisplay
    case writerUnavailable
    case invalidAudioFormat
    case audioBufferList(OSStatus)
    case noAudioFrames

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "録音対象のディスプレイを取得できませんでした。"
        case .writerUnavailable:
            return "録音データの保存処理を開始できませんでした。"
        case .invalidAudioFormat:
            return "システム音声の形式を読み取れませんでした。"
        case .audioBufferList(let status):
            return "音声バッファを読み取れませんでした（OSStatus \(status)）。"
        case .noAudioFrames:
            return "音声データを取得できませんでした。再生中の音がある状態でもう一度試してください。"
        }
    }
}

private final class AudioSampleBufferWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    private let outputURL: URL
    private let levelHandler: @Sendable (Float) -> Void
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private var firstError: Error?
    private var framesWritten: Int64 = 0
    private var isFinished = false
    private var lastMeterUpdate: CFAbsoluteTime = 0

    init(outputURL: URL, levelHandler: @escaping @Sendable (Float) -> Void) {
        self.outputURL = outputURL
        self.levelHandler = levelHandler
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, firstError == nil else { return }

        do {
            try append(sampleBuffer)
        } catch {
            firstError = error
        }
    }

    func finish() throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        isFinished = true
        audioFile = nil

        if let firstError {
            try? FileManager.default.removeItem(at: outputURL)
            throw firstError
        }
        guard framesWritten > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw RecorderError.noAudioFrames
        }
        return outputURL
    }

    private func append(_ sampleBuffer: CMSampleBuffer) throws {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw RecorderError.invalidAudioFormat
        }

        var asbd = streamDescription.pointee
        guard let inputFormat = AVAudioFormat(streamDescription: &asbd) else {
            throw RecorderError.invalidAudioFormat
        }

        let maximumBuffers = max(1, Int(inputFormat.channelCount))
        let bufferListSize = MemoryLayout<AudioBufferList>.size
            + max(0, maximumBuffers - 1) * MemoryLayout<AudioBuffer>.size
        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let bufferListPointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferListPointer,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else {
            throw RecorderError.audioBufferList(status)
        }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            bufferListNoCopy: bufferListPointer,
            deallocator: nil
        ) else {
            throw RecorderError.invalidAudioFormat
        }
        pcmBuffer.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        emitLevelIfNeeded(from: pcmBuffer)

        if audioFile == nil {
            audioFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
        }

        try audioFile?.write(from: pcmBuffer)
        framesWritten += Int64(pcmBuffer.frameLength)
    }

    private func emitLevelIfNeeded(from buffer: AVAudioPCMBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastMeterUpdate >= 0.05 else { return }
        lastMeterUpdate = now

        guard let channels = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var peak: Float = 0

        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameCount {
                peak = max(peak, abs(samples[frame]))
            }
        }

        levelHandler(peak)
    }
}
