# BackAudioRecorder

Macで再生中の**システム音声だけ**を、1ボタンで録音・停止し、WAVとして自動保存する小さなネイティブmacOSアプリです。マイク入力は使用しません。録音中のリアルタイム波形、自動前後トリミング、前面固定にも対応します。

## ダウンロード

最新版は [GitHub Releases](https://github.com/uniplanck/BackAudioRecorder/releases/latest) から `BackAudioRecorder-v1.0.0-macOS.zip` をダウンロードできます。

- 対応OS: macOS 14 Sonoma以降
- 現在の配布版はDeveloper ID署名・notarization前のため、初回起動時にmacOSの警告が出る場合があります。その場合はFinderでアプリを右クリックして「開く」を選択してください。

## 使い方

1. `BackAudioRecorder.app` を開く。
2. 中央の録音ボタンを押す。
3. 初回だけ macOS の「画面とシステムオーディオ録音」を許可する。
4. 同じボタンをもう一度押すと停止し、自動でWAV保存される。

追加機能:

- 左上のハサミアイコン: 自動トリミングON/OFF。ON時は先頭・末尾の無音を自動カットし、設定したPre/Postパディングを残す。
- 自動トリミング初期値: Pre 1.0秒 / Post 2.0秒 / 無音境界 -50 dBFS。
- 録音中: Window内にリアルタイム音声波形を表示。
- 右上のピンアイコン: Windowを前面固定 / 解除。
- パディング設定はUserDefaultsへ保存し、次回起動時も維持。

保存先:

```text
~/Music/BackAudioRecorder/BackAudio-YYYYMMDD-HHmmss.wav
```

## ビルド

```zsh
git clone https://github.com/uniplanck/BackAudioRecorder.git
cd BackAudioRecorder
zsh scripts/build-app.sh
```

生成物:

```text
dist/BackAudioRecorder.app
```

## 実装

- SwiftUI
- ScreenCaptureKit
- AVFoundation / AVAudioFile
- 48 kHz / 2 ch
- `capturesAudio = true`
- `excludesCurrentProcessAudio = true`
- マイクAPIは使用しない

ScreenCaptureKitの仕様上、音声だけを取得する場合でもmacOSの画面・システムオーディオ録音権限が必要です。
