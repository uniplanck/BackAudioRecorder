import AppKit
import SwiftUI

@main
struct BackAudioRecorderApp: App {
    @StateObject private var recorder = SystemAudioRecorder()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var recorder: SystemAudioRecorder
    @State private var isPinned = false

    private let paddingChoices: [Double] = [0, 0.25, 0.5, 1, 1.5, 2, 3, 5]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                trimToggle
                Spacer()
                pinButton
            }

            VStack(spacing: 5) {
                Text("System Audio")
                    .font(.system(size: 20, weight: .semibold))
                Text(recorder.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if recorder.autoTrimEnabled {
                trimSettings
            }

            waveformArea

            Button {
                Task { await recorder.toggle() }
            } label: {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 92, height: 92)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle.fill")
                        .font(.system(size: recorder.isRecording ? 30 : 38, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(recorder.isBusy)
            .accessibilityLabel(recorder.isRecording ? "録音を停止してWAV保存" : "システム音声の録音を開始")

            Group {
                if recorder.isRecording, let startedAt = recorder.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(elapsedText(from: startedAt, to: timeline.date))
                            .font(.system(.body, design: .monospaced).monospacedDigit())
                    }
                } else if let savedURL = recorder.lastSavedURL {
                    VStack(spacing: 3) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                        } label: {
                            Label("保存したWAVを表示", systemImage: "folder")
                        }
                        .buttonStyle(.link)

                        if let trimSummary = recorder.trimSummary {
                            Text(trimSummary)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("停止すると自動でWAV保存")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 34)

            if let error = recorder.errorMessage {
                VStack(spacing: 6) {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Button("録音権限の設定を開く") {
                        recorder.openScreenRecordingSettings()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
                .frame(maxWidth: 330)
            }
        }
        .padding(20)
        .frame(width: 390)
        .frame(minHeight: 350)
        .background(.background)
    }

    private var trimToggle: some View {
        Button {
            recorder.autoTrimEnabled.toggle()
        } label: {
            Image(systemName: "scissors")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(recorder.autoTrimEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(recorder.autoTrimEnabled ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(recorder.isRecording || recorder.isBusy)
        .help(recorder.autoTrimEnabled ? "自動トリミング ON" : "自動トリミング OFF")
        .accessibilityLabel("自動トリミング")
        .accessibilityValue(recorder.autoTrimEnabled ? "オン" : "オフ")
    }

    private var pinButton: some View {
        Button {
            togglePinned()
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isPinned ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help(isPinned ? "前面固定を解除" : "前面に固定")
        .accessibilityLabel("前面固定")
        .accessibilityValue(isPinned ? "固定中" : "通常")
    }

    private var trimSettings: some View {
        Menu {
            Menu("開始前パディング") {
                ForEach(paddingChoices, id: \.self) { value in
                    Button {
                        recorder.preRollSeconds = value
                    } label: {
                        if recorder.preRollSeconds == value {
                            Label(formatSeconds(value), systemImage: "checkmark")
                        } else {
                            Text(formatSeconds(value))
                        }
                    }
                }
            }

            Menu("終了後パディング") {
                ForEach(paddingChoices, id: \.self) { value in
                    Button {
                        recorder.postRollSeconds = value
                    } label: {
                        if recorder.postRollSeconds == value {
                            Label(formatSeconds(value), systemImage: "checkmark")
                        } else {
                            Text(formatSeconds(value))
                        }
                    }
                }
            }
        } label: {
            Label(
                "Pre \(formatSeconds(recorder.preRollSeconds)) · Post \(formatSeconds(recorder.postRollSeconds))",
                systemImage: "slider.horizontal.3"
            )
            .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(recorder.isRecording || recorder.isBusy)
        .help("自動トリミング後に残す前後の無音時間")
        .accessibilityLabel("トリミングパディング設定")
    }

    private var waveformArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.06))

            if recorder.isRecording {
                WaveformView(levels: recorder.waveformLevels)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("録音波形")
                    .accessibilityValue("リアルタイム")
            }
        }
        .frame(height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("録音波形")
        .accessibilityValue(recorder.isRecording ? "リアルタイム" : "待機中")
        .accessibilityHidden(!recorder.isRecording)
    }

    private func togglePinned() {
        isPinned.toggle()
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        window?.level = isPinned ? .floating : .normal
    }

    private func formatSeconds(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0fs", value)
        }
        return String(format: "%.2gs", value)
    }

    private func elapsedText(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

private struct WaveformView: View {
    let levels: [Double]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(2, proxy.size.height * max(0.04, level)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}
