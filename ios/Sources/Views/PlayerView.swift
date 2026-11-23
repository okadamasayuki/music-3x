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
    /// 操作盤を下へ畳んでいるか。字幕を広く読みたいとき用。次に開いたときも保つ。
    @AppStorage("playerDockCollapsed") private var dockCollapsed = false
    /// 操作盤をなぞって動かしている量
    @State private var dockDrag: CGFloat = 0
    /// いまのなぞりが縦向きか。横向きなら再生バーの操作なので盤は動かさない。
    @State private var dockDragIsVertical: Bool?
    /// 開いたときの盤の高さ。なぞりに合わせて字幕の領域を広げ縮めするのに使う。
    @State private var panelHeight: CGFloat = 0

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
        // 横から入ってくる間に後ろの画面が透けないよう、自前の下地を持つ。
        // 聞き取りテストと同じ暗い紺にして、行き来しても見た目が切り替わらないようにする。
        .background(NightBackdrop().ignoresSafeArea())
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        // 盤を畳んでいる間は、下端から上へのなぞりをまず盤を開く操作として受ける。
        // そのままだとホームバーの操作に取られてホーム画面へ戻ってしまう。
        .defersSystemGestures(on: dockCollapsed ? .bottom : [])
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("一覧へ戻る")
            .accessibilityIdentifier("playerClose")

            VStack(alignment: .leading, spacing: 2) {
                Text("NOW PLAYING")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Night.cyan)
                Text(liveTrack.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 聞き取りテストと同じ物差し(教材全体の何項目目か)
            Text(positionCaption)
                .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .accessibilityIdentifier("playerPosition")

            if isLive, !player.groups.isEmpty {
                LearnedRing(learned: player.learnedGroups.count, total: player.groups.count)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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

            controlPanel
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
                })
                .padding(.horizontal, 12)
                // 畳むときは盤を大きさそのままで画面の下へ沈め、上端だけを覗かせる。
                // 置き場所の高さを詰めると中身は縮まずに下へはみ出して見え、同時に
                // 字幕の領域が広がる。なぞっている途中もこの高さを指に合わせて変えるので、
                // 下げるにつれて単語が下からぞろぞろ現れる。
                .frame(height: dockLayoutHeight, alignment: .top)
                .offset(y: dockOverPull)
        }
        .onPreferenceChange(PanelHeightKey.self) { height in
            if height > 0 { panelHeight = height }
        }
        // 開いているときは少し下へ寄せる(ホームバーの手前までは使ってよい)。
        // 畳んだときは、覗かせる部分がホームバーの操作域に重ならないよう安全域の上に置く。
        .padding(.bottom, dockCollapsed ? 0 : -14)
        // 盤の後ろで字幕がふっと消えるようにする。盤のまわりの隙間に文字が
        // 透けて見えると落ち着かないため。すりガラスは使わない(OpaqueBar 参照)。
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: Night.indigo.opacity(0), location: 0),
                    .init(color: Night.indigo, location: 0.35),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .padding(.top, -24)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    /// 再生ボタンの両脇の札の幅。左右をそろえて再生ボタンを真ん中に見せる。
    private static let sideChipWidth: CGFloat = 104

    /// 畳んだ盤が安全域の上へ覗く高さ。つまみを押さえられる分だけ出す
    /// (その下にもホームバーの分だけ盤が見える)。
    private static let dockPeek: CGFloat = 30

    /// 盤の置き場所の高さ。nil なら盤そのものの高さ。
    private var dockLayoutHeight: CGFloat? {
        let full = panelHeight
        if dockCollapsed {
            guard full > 0 else { return Self.dockPeek }
            // 上へなぞった分だけ、隠れていた部分を出していく
            return min(full, Self.dockPeek + max(0, -dockDrag))
        }
        guard full > 0, dockDrag > 0 else { return nil }
        // 下へなぞった分だけ沈める。開いているときは 14 下げてあるので、その分を足して止める
        return max(Self.dockPeek + 14, full - dockDrag)
    }

    /// 行き止まりの向きへ引いたときの、重い手ごたえ
    private var dockOverPull: CGFloat {
        if dockCollapsed { return dockDrag > 0 ? dockDrag / 4 : 0 }
        return dockDrag < 0 ? dockDrag / 4 : 0
    }

    /// 操作盤。上端のつまみのあたりを下へなぞると畳め、上へなぞるか押すと開く。
    private var controlPanel: some View {
        VStack(spacing: 0) {
            DockGrabber()
                .padding(.top, 8)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                if settings.voiceControl {
                    voiceStrip.padding(.bottom, 8)
                }
                seekSection
                mainRow
                    .padding(.top, 6)
                adjustRow
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .background(DockCard())
        .contentShape(Rectangle())
        .onTapGesture { if dockCollapsed { setDock(collapsed: false) } }
        // 中の再生バーと取り合わないよう、同時に受けて縦の動きだけを拾う
        // (再生バーは横の動きだけを拾う)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    if dockDragIsVertical == nil {
                        dockDragIsVertical = abs(value.translation.height) > abs(value.translation.width)
                    }
                    guard dockDragIsVertical == true else { return }
                    dockDrag = value.translation.height
                }
                .onEnded { value in
                    defer { dockDragIsVertical = nil }
                    guard dockDragIsVertical == true else { return }
                    let down = value.translation.height
                    let flung = value.predictedEndTranslation.height
                    if dockCollapsed {
                        setDock(collapsed: !(down < -30 || flung < -100))
                    } else {
                        setDock(collapsed: down > 50 || flung > 150)
                    }
                }
        )
        .accessibilityAction(named: dockCollapsed ? "操作盤を開く" : "操作盤を畳む") {
            setDock(collapsed: !dockCollapsed)
        }
    }

    private func setDock(collapsed: Bool) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            dockCollapsed = collapsed
            dockDrag = 0
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
                            .foregroundStyle(index == 0 ? Color.white : Color.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .dynamicTypeSize(settings.textSize)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
        VStack(spacing: 1) {
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
            .foregroundStyle(.white.opacity(0.55))
        }
    }


    // MARK: - 再生コントロール

    /// 再生ボタンを真ん中に置き、訳とテストを同じ幅の札で両脇に添える。
    /// 前後の項目へ飛ぶボタンは使わないので置かない(一覧で二度押しすれば飛べる)。
    private var mainRow: some View {
        ZStack {
            HStack {
                TranslationToggle(width: Self.sideChipWidth)
                Spacer()
                listeningTestButton
            }
            playButton
        }
    }

    /// 文字の大きさと再生速度。どちらも一段ずつ動かす同じ形の札にそろえる。
    private var adjustRow: some View {
        HStack {
            textSizeStepper
            Spacer(minLength: 8)
            speedStepper
        }
    }

    /// 字幕の文字の大きさ。設定画面のつまみと同じ値を動かす。
    private var textSizeStepper: some View {
        let step = settings.textSizeStep
        let last = AppSettings.textSizes.count - 1
        return HStack(spacing: 0) {
            Button {
                settings.textSizeStep = max(0, step - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 36, height: 34)
                    .contentShape(Rectangle())
            }
            .disabled(step <= 0)
            .opacity(step <= 0 ? 0.3 : 1)
            .accessibilityIdentifier("textSmaller")
            .accessibilityLabel("文字を小さく")

            Image(systemName: "textformat.size")
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 44)
                .accessibilityLabel("文字の大きさ \(settings.textSizeLabel)")

            Button {
                settings.textSizeStep = min(last, step + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 36, height: 34)
                    .contentShape(Rectangle())
            }
            .disabled(step >= last)
            .opacity(step >= last ? 0.3 : 1)
            .accessibilityIdentifier("textLarger")
            .accessibilityLabel("文字を大きく")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Capsule().fill(Color.white.opacity(0.09)))
    }

    /// 聞き取りテストを開くボタン。英語だけを聞いて、訳が浮かぶかを確かめる。
    /// 問題は字幕から作るので、字幕のない音源では押せない。
    private var listeningTestButton: some View {
        let enabled = library.subtitleURL(for: liveTrack) != nil
        return Button {
            showListeningTest = true
        } label: {
            Label("テスト", systemImage: "ear")
                .chipLabel(active: false, width: Self.sideChipWidth)
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
        .foregroundStyle(.white)
        .background(Capsule().fill(Color.white.opacity(0.09)))
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

    private var playButton: some View {
        let showsPause = isLive && player.isPlaying
        return Button {
            if isLive { player.togglePlayPause() } else { switchToThisTrack() }
        } label: {
            ZStack {
                Circle()
                    .fill(Night.glow)
                    .shadow(color: Night.blue.opacity(0.55), radius: 16, x: 0, y: 6)
                Image(systemName: showsPause ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    // 三角は見た目の重心が左に寄るので、少しだけ右へずらす
                    .offset(x: showsPause ? 0 : 2)
            }
            .frame(width: 66, height: 66)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isLive && !player.isReady)
        .accessibilityIdentifier(isLive ? "transport" : "switchToTrack")
        .accessibilityLabel(showsPause ? "一時停止" : "再生")
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
    /// いまのなぞりが横向きか(最初の動きで決める)
    @State private var isHorizontal: Bool?

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [Night.cyan, Night.blue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(width * fraction, isDragging ? 10 : 5))
                    .shadow(color: Night.cyan.opacity(0.5), radius: 6)
            }
            .frame(height: isDragging ? 10 : 5)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 3)
            .contentShape(Rectangle())
            // 横へ動かしたときだけ再生位置を動かす。触れただけや縦のなぞり
            // (操作盤を畳む動き)では動かさない。
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        if isHorizontal == nil {
                            isHorizontal = abs(drag.translation.width) > abs(drag.translation.height)
                        }
                        guard isHorizontal == true else { return }
                        if !isDragging {
                            isDragging = true
                            onBegin()
                        }
                        onChange(position(drag.location.x, width: width))
                    }
                    .onEnded { drag in
                        defer { isHorizontal = nil }
                        guard isEnabled, isDragging else { return }
                        isDragging = false
                        onEnd(position(drag.location.x, width: width))
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        }
        .frame(height: 20)
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

/// 覚えた数を小さな輪で示す。輪の満ち具合が全体に対する割合。
private struct LearnedRing: View {
    let learned: Int
    let total: Int

    private var fraction: Double { total > 0 ? Double(learned) / Double(total) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    LinearGradient(colors: [Night.green, Night.cyan], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(learned)")
                .font(.system(size: learned >= 100 ? 10 : 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .padding(4)
        }
        .frame(width: 38, height: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("覚えた項目 \(learned) / \(total)")
    }
}

extension View {
    /// 操作盤の札の見た目。訳・テスト・速度で形をそろえる。
    func chipLabel(active: Bool, width: CGFloat? = nil) -> some View {
        self
            .font(.footnote.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .frame(width: width, height: 34)
            .foregroundStyle(Color.white)
            .background {
                if active {
                    Capsule().fill(Night.glow)
                } else {
                    Capsule().fill(Color.white.opacity(0.09))
                }
            }
            .contentShape(Capsule())
    }
}

/// 操作盤の下地。字幕の上に浮いた札に見せる。
private struct DockCard: View {
    var body: some View {
        // 下を字幕が流れるので、透けない地にする(GlassCard は透ける)
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Night.card)
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
            .overlay(GlassEdge(cornerRadius: 28))
    }
}

/// 畳む・開くのつまみ
private struct DockGrabber: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.25))
            .frame(width: 36, height: 5)
    }
}

/// 開いた操作盤の高さを外へ伝える
private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

