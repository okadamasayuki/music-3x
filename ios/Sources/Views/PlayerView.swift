import SwiftUI

struct PlayerView: View {
    let track: Track
    /// 今かかっている項目の字幕。別の音源を開いている間、小さい操作板に出す。
    var nowPlayingLines: [String] = []
    /// 今かかっている音源のプレイヤーを開く。小さい操作板を押したときに使う。
    var onOpenNowPlaying: () -> Void = {}
    /// 戻るなぞり操作の進み具合。重なりを管理している側へ渡す。
    var onBackDragChanged: (CGFloat) -> Void = { _ in }
    var onBackDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
    /// 左上の戻る。なぞって戻すのと同じ道をたどる
    var onClose: () -> Void = {}

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var voice: VoiceCommands

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    /// 別の音源が鳴っている間に開いたときの、下読み用の字幕。
    /// 音を止めずに中身だけ見られるよう、再生機とは別に読み込む。
    @State private var previewCues: [SubtitleCue] = []
    @State private var previewGroups: [SubtitleGroup] = []
    /// 聞き取りテストを開いているか
    @State private var showListeningTest = false

    /// この画面の音源が、いま再生機に載っているか。
    private var isLive: Bool { player.currentTrackID == track.id }

    /// いま鳴っている音源(この画面のものとは限らない)
    private var playingTrack: Track? {
        player.currentTrackID.flatMap { id in library.tracks.first { $0.id == id } }
    }

    /// ライブラリ側が更新される(字幕を後から足す等)ので、常に最新を引き直す。
    private var liveTrack: Track {
        library.tracks.first(where: { $0.id == track.id }) ?? track
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if isLive {
                    TranscriptView(onToggleLearned: setLearned)
                } else {
                    previewList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 戻る操作は字幕の領域だけで受ける。下の操作部に付けると、
            // 再生位置のバーを横に動かしただけで戻ってしまう。
            .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
            // 見出しの下へ字幕が切れ目なく溶け込むよう、上端だけ薄く消す
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.03),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // 操作盤は字幕の上に浮かせる。字幕はその下までスクロールでき、
            // 最後の項目も盤に隠れず読める位置まで上げられる。
            .safeAreaInset(edge: .bottom, spacing: 0) { dock }
        }
        // 横から入ってくる間に後ろの画面が透けないよう、自前の下地を持つ
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear(perform: loadIfNeeded)
        .fullScreenCover(isPresented: $showListeningTest) {
            ListeningTestView(track: liveTrack, onClose: { showListeningTest = false })
        }
        // 検証用の合図でテストを開ける(TestSignals 参照)
        .onReceive(NotificationCenter.default.publisher(for: .music3xListeningTest)) { note in
            if note.userInfo?["action"] as? String == "open" { showListeningTest = true }
        }
    }

    // MARK: - 見出し

    /// 何の教材の、どこを聞いているか。覚えた割合も輪で添える。
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("一覧へ戻る")
            .accessibilityIdentifier("playerClose")

            VStack(alignment: .leading, spacing: 2) {
                Text(liveTrack.displayName)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                Text(positionCaption)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isLive, !player.groups.isEmpty {
                LearnedRing(learned: player.learnedGroups.count, total: player.groups.count)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// 「28 / 852」のように今の項目の位置を示す。下読み中は項目数だけ。
    private var positionCaption: String {
        if isLive {
            let total = player.groups.count
            guard total > 0 else { return "字幕なし" }
            let current = (player.currentGroupIndex ?? player.highlightedGroupIndex ?? 0) + 1
            return "\(current) / \(total)"
        }
        return previewGroups.isEmpty ? "" : "\(previewGroups.count) 項目"
    }

    // MARK: - 操作盤

    /// 画面の下に浮かせた操作盤。別の音源が鳴っている間は、その札を上に重ねる。
    private var dock: some View {
        VStack(spacing: 10) {
            if !isLive, let playing = playingTrack {
                MiniPlayerBar(
                    title: playing.displayName,
                    lines: nowPlayingLines,
                    isPlaying: player.isPlaying,
                    progress: player.effectiveDuration > 0
                        ? player.effectiveTime(for: player.currentTime) / player.effectiveDuration
                        : 0,
                    onOpen: onOpenNowPlaying,
                    onToggle: { player.togglePlayPause() }
                )
            }

            VStack(spacing: 14) {
                if settings.voiceControl { voiceStrip }
                seekSection
                transportButtons
                utilityRow
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
        // 盤の後ろで字幕がふっと消えるようにする。盤のまわりの隙間に文字が
        // 透けて見えると落ち着かないため。すりガラスは使わない(OpaqueBar 参照)。
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: Color(.systemBackground).opacity(0), location: 0),
                    .init(color: Color(.systemBackground), location: 0.35),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .padding(.top, -24)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    // MARK: - 別の音源が鳴っている間の下読み

    /// 音を止めずに中身だけ並べる。印は付けられない(再生機を通さないため)ので、
    /// 印を付けたいときはフレーズタブを使う。
    private var previewList: some View {
        List {
            ForEach(previewGroups) { group in
                let lines = group.lines(in: previewCues)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        Text(line.text)
                            .font(index == 0 ? .body : .subheadline)
                            .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .dynamicTypeSize(settings.textSize)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("previewList")
    }


    /// 声をどう聞き取ったかを、聞きながら確かめられるように出す。
    /// 反応しないとき、何に化けているのかが分からないと直しようがないため。
    private var voiceStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: voice.isListening ? "mic.fill" : "mic.slash.fill")
                .font(.caption2)
                .foregroundStyle(voice.isListening
                                 ? (voice.echoCancelled ? Color.green : Color.orange)
                                 : Color.secondary)

            if let problem = voice.problem {
                Text(problem)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                // 聞き取った言葉は末尾を見せる。前の分は流れていくだけなので。
                Text(voice.lastHeard.isEmpty
                     ? "「\(VoiceCommands.primaryTrigger) 単語」と言ってください"
                     : voice.lastHeard)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("voiceHeard")

                if !voice.lastMatched.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: voice.lastUndone ? "arrow.uturn.backward"
                              : voice.lastMatchedBecameLearned ? "checkmark.circle.fill" : "circle")
                        // 少し違って聞こえた場合は、どう化けたのかも添える
                        Text(voice.lastMatchedHeardAs == voice.lastMatched
                             ? voice.lastMatched
                             : "\(voice.lastMatched) ←「\(voice.lastMatchedHeardAs)」")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(voice.lastMatchedBecameLearned ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("voiceMatched")
                    .accessibilityLabel(voice.lastMatchedBecameLearned
                                        ? "\(voice.lastMatched) に覚えた印を付けました"
                                        : "\(voice.lastMatched) の覚えた印を外しました")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - シーク

    /// 覚えて飛ばす分を除いた時間軸で表示する。聞く分量と目盛りを一致させるため。
    private var displayedTime: Double {
        isScrubbing ? scrubValue : player.effectiveTime(for: player.currentTime)
    }

    private var seekSection: some View {
        VStack(spacing: 6) {
            Scrubber(
                value: displayedTime,
                total: player.effectiveDuration,
                isEnabled: isLive && player.effectiveDuration > 0,
                onBegin: {
                    isScrubbing = true
                    scrubValue = player.effectiveTime(for: player.currentTime)
                    player.beginScrubbing()
                },
                onChange: { newValue in
                    scrubValue = newValue
                    player.previewScrub(to: player.realTime(for: newValue))
                },
                onEnd: { newValue in
                    scrubValue = newValue
                    isScrubbing = false
                    player.endScrubbing(at: player.realTime(for: newValue))
                }
            )

            HStack {
                Text(TimeFormatter.string(from: displayedTime))
                    .accessibilityIdentifier("elapsed")
                Spacer()
                Text(TimeFormatter.string(from: player.effectiveDuration))
                    .accessibilityIdentifier("duration")
            }
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
        }
    }


    // MARK: - 再生コントロール

    /// 訳・テスト・速度を同じ形の札で一列に並べる。
    /// 再生ボタンの両脇へ縦に積むと、寄せ集めに見えるうえ押し分けにくかった。
    private var utilityRow: some View {
        HStack(spacing: 8) {
            TranslationToggle()
            listeningTestButton
            Spacer(minLength: 8)
            speedStepper
        }
    }

    /// 聞き取りテストを開くボタン。英語だけを聞いて、訳が浮かぶかを確かめる。
    /// 問題は字幕から作るので、字幕のない音源では押せない。
    private var listeningTestButton: some View {
        let enabled = library.subtitleURL(for: liveTrack) != nil
        return Button {
            showListeningTest = true
        } label: {
            Label("テスト", systemImage: "ear")
                .chipLabel(active: false)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel("聞き取りテスト")
        .accessibilityIdentifier("listeningTestOpen")
    }

    /// 再生速度。一覧から選ばせる形だと、行が狭いうえ真下に再生ボタンがあり、
    /// 押し損ねると何も起きずに閉じるだけになる。一段ずつ動かす形にして、
    /// 一度押せば必ず変わるようにした。
    private var speedStepper: some View {
        HStack(spacing: 0) {
            Button {
                stepSpeed(-1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 36, height: 34)
                    .contentShape(Rectangle())
            }
            .disabled(!canStepSpeed(-1))
            .opacity(canStepSpeed(-1) ? 1 : 0.3)
            .accessibilityIdentifier("speedDown")
            .accessibilityLabel("速度を下げる")

            Text(SpeedFormatter.label(for: player.speed))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 44)
                .accessibilityIdentifier("speed")
                .accessibilityLabel("再生速度 \(SpeedFormatter.label(for: player.speed))")

            Button {
                stepSpeed(1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 36, height: 34)
                    .contentShape(Rectangle())
            }
            .disabled(!canStepSpeed(1))
            .opacity(canStepSpeed(1) ? 1 : 0.3)
            .accessibilityIdentifier("speedUp")
            .accessibilityLabel("速度を上げる")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    /// 今の速度が刻みの何番目か。刻みに無い値なら、それ以下で一番近いものとみなす。
    private var speedIndex: Int {
        let choices = AppSettings.speedChoices
        if let exact = choices.firstIndex(where: { abs($0 - player.speed) < 0.001 }) { return exact }
        return choices.lastIndex(where: { $0 <= player.speed }) ?? 0
    }

    private func canStepSpeed(_ direction: Int) -> Bool {
        AppSettings.speedChoices.indices.contains(speedIndex + direction)
    }

    private func stepSpeed(_ direction: Int) {
        let target = speedIndex + direction
        guard AppSettings.speedChoices.indices.contains(target) else { return }
        apply(speed: AppSettings.speedChoices[target])
    }

    private var transportButtons: some View {
        // 秒数で送るより教材の切れ目で動くほうが聞き直しやすいので、
        // 送り戻しは前後の塊への移動にしてある。
        let canPrev = isLive && player.hasPreviousGroup
        let canNext = isLive && player.hasNextGroup
        let showsPause = isLive && player.isPlaying
        return HStack(spacing: 40) {
            Button {
                player.goToPreviousGroup()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .disabled(!canPrev)
            .opacity(canPrev ? 1 : 0.25)
            .accessibilityIdentifier("previousGroup")
            .accessibilityLabel("前の塊へ")

            Button {
                if isLive { player.togglePlayPause() } else { switchToThisTrack() }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 12, x: 0, y: 6)
                    Image(systemName: showsPause ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        // 三角は見た目の重心が左に寄るので、少しだけ右へずらす
                        .offset(x: showsPause ? 0 : 2)
                }
                .frame(width: 72, height: 72)
                .contentShape(Circle())
            }
            .disabled(isLive && !player.isReady)
            .accessibilityIdentifier(isLive ? "transport" : "switchToTrack")
            .accessibilityLabel(showsPause ? "一時停止" : "再生")

            Button {
                player.goToNextGroup()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .disabled(!canNext)
            .opacity(canNext ? 1 : 0.25)
            .accessibilityIdentifier("nextGroup")
            .accessibilityLabel("次の塊へ")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - 処理

    /// 鳴っている音にその場で効かせ、次に開いたときも同じ速さで始まるようにする。
    private func apply(speed: Double) {
        player.speed = speed
        settings.defaultSpeed = speed
    }

    private func setLearned(_ group: Int, _ learned: Bool) {
        player.setLearned(learned, group: group)
        library.setLearned(learned, group: group, cueCount: player.cues.count, for: track.id)
    }


    private func loadIfNeeded() {
        guard !isLive else { return }
        // 鳴っている最中に別の音源を開いても、音は止めない。中身だけ読んで並べ、
        // 切り替えるかどうかは「この音源を再生」を押したときに決める。
        if player.isPlaying {
            loadPreview()
            return
        }
        loadIntoPlayer()
    }

    private func loadPreview() {
        guard previewGroups.isEmpty else { return }
        guard let url = library.subtitleURL(for: liveTrack) else { return }
        let content = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .shiftJIS)) ?? ""
        previewCues = SubtitleParser.parse(content)
        previewGroups = previewCues.grouped()
    }

    private func loadIntoPlayer() {
        let current = liveTrack
        player.load(
            audioURL: library.audioURL(for: current),
            subtitleURL: library.subtitleURL(for: current),
            title: current.displayName,
            trackID: current.id,
            startAt: current.lastPosition
        )
        player.applyLearned(library.learnedGroups(for: current.id, cueCount: player.cues.count))
        player.speed = settings.defaultSpeed
    }

    /// 下読みしていた音源へ切り替えて鳴らし始める。
    private func switchToThisTrack() {
        loadIntoPlayer()
        previewCues = []
        previewGroups = []
        player.play()
    }
}

// MARK: - 部品

/// 再生位置のバー。ふだんは細く、触っている間だけ太くして掴んだことを示す。
/// 標準のスライダーは丸いつまみが大きく、細い操作盤の中で浮いて見えたため自前にした。
private struct Scrubber: View {
    let value: Double
    let total: Double
    let isEnabled: Bool
    var onBegin: () -> Void
    var onChange: (Double) -> Void
    var onEnd: (Double) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(width * fraction, isDragging ? 10 : 5))
            }
            .frame(height: isDragging ? 10 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        if !isDragging {
                            isDragging = true
                            onBegin()
                        }
                        onChange(position(drag.location.x, width: width))
                    }
                    .onEnded { drag in
                        guard isEnabled, isDragging else { return }
                        isDragging = false
                        onEnd(position(drag.location.x, width: width))
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("再生位置")
        .accessibilityValue(TimeFormatter.string(from: value))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let step = 15.0
            let target = direction == .increment ? value + step : value - step
            onBegin()
            onEnd(min(max(target, 0), total))
        }
    }

    private func position(_ x: CGFloat, width: CGFloat) -> Double {
        Double(min(max(x / width, 0), 1)) * total
    }
}

/// 覚えた割合を小さな輪で示す。
private struct LearnedRing: View {
    let learned: Int
    let total: Int

    private var fraction: Double { total > 0 ? Double(learned) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("覚えた")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(learned)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("覚えた項目 \(learned) / \(total)")
    }
}

extension View {
    /// 操作盤の札の見た目。訳・テスト・速度で形をそろえる。
    func chipLabel(active: Bool) -> some View {
        self
            .font(.footnote.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(Capsule().fill(active ? Color.accentColor : Color.primary.opacity(0.07)))
            .contentShape(Capsule())
    }
}

