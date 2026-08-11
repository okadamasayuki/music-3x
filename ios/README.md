# 倍速プレイヤー — iOS 版

Web 版(リポジトリ直下の `index.html`)と同じ「倍速再生 + 字幕同期」を、
SwiftUI + AVFoundation でネイティブアプリとして作り直したものです。

## Web 版との違い

ネイティブにしたことで、ブラウザではできなかったことができます。

| | Web 版 | iOS 版 |
| --- | --- | --- |
| 倍速 | ブラウザ依存(iOS Safari は不安定) | AVPlayer で 0.5x〜4.0x を安定再生 |
| 画面を消したら | 停止する | バックグラウンドで再生継続 |
| ロック画面 | 操作不可 | 再生 / 停止 / 10秒送り戻し / シーク |
| 音源 | 毎回ファイル選択 | 端末内に保存してライブラリ管理 |
| 続きから再生 | なし | 前回の停止位置を記憶 |
| 消音スイッチ | 影響を受ける | `.playback` カテゴリで鳴る |

## 必要なもの

- **Xcode**(App Store から入手。Command Line Tools だけでは開けません)
- iOS 16.0 以降の実機、またはシミュレータ
- 実機で動かす場合のみ Apple ID(無料。App Store 公開時のみ有料の Developer Program が必要)

## 開き方

```sh
cd ios
open Music3x.xcodeproj
```

実機に入れる場合は、Xcode で `Music3x` ターゲットの **Signing & Capabilities** を開き、
Team に自分の Apple ID を選んでください。`project.yml` の `DEVELOPMENT_TEAM` に
チーム ID を書いておけば、次回以降の生成で自動的に設定されます。

## プロジェクトの再生成

`.xcodeproj` は [XcodeGen](https://github.com/yonaskolb/XcodeGen) で `project.yml` から生成しています。
ソースファイルを追加・削除したら、次を実行すれば構成が更新されます。

```sh
cd ios
xcodegen generate
```

`Sources/` 配下は自動で拾われるので、通常 `project.yml` を触る必要はありません。

## 音源と字幕の入れ方

アプリ内の「＋」から「ファイル」アプリ経由で読み込むほか、
Finder で iPhone を繋いで **ファイル → Music3x** に直接ドラッグしても入ります
(`UIFileSharingEnabled` を有効にしてあります)。

直接置かれたファイルは、アプリを起動したときと前面に戻したときに自動で拾われ、
一覧に追加されます。`library.json` を手で書く必要はありません。

字幕は SRT / WebVTT に対応しています。音源と同じ名前の字幕ファイル
(例: `lesson01.mp3` と `lesson01.srt`)を入れておくと、取り込み時に自動で紐付きます。

## 構成

| ファイル | 役割 |
| --- | --- |
| `Sources/Music3xApp.swift` | エントリポイント |
| `Sources/Model/SubtitleCue.swift` | SRT / VTT パーサーと二分探索 |
| `Sources/Model/Track.swift` | 音源 1 件を表すモデル |
| `Sources/Model/LibraryStore.swift` | 端末内のファイル管理と永続化 |
| `Sources/Player/PlayerEngine.swift` | AVPlayer のラッパー。倍速・字幕同期・ロック画面 |
| `Sources/Views/` | SwiftUI の画面一式 |
| `project.yml` | XcodeGen のプロジェクト定義 |

## 実装上のポイント

- **音程の維持**: `AVAudioTimePitchAlgorithm.spectral` を使い、4x でも声が高くなりません。
  オフにすると `.varispeed`(テープ早回し相当)に切り替わります。
- **字幕の同期**: 0.1 秒ごとのタイムオブザーバで現在位置を見て、
  直前のキューが有効なら探索を省略、切り替わったときだけ二分探索します。
- **バックグラウンド再生**: `UIBackgroundModes: audio` と
  `AVAudioSession` の `.playback` カテゴリの両方が必要です。片方だけでは止まります。
