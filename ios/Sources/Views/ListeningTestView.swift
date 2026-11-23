import SwiftUI
import UIKit

/// 英語を聞いて、訳が浮かぶかを確かめるテスト。
///
/// 覚えた印の付いていない項目だけを出題する。項目の英語の部分だけを鳴らし、
/// 画面には答えを出さない。鳴り終えてから決めた秒数が経つと英文と訳が現れ、
/// 「覚えた」を押すと英→日タブの覚えた印にもそのまま付く。
///
/// 項目をまるごと鳴らすと訳まで読み上げて答えが聞こえてしまうので、
/// 鳴らすのは項目の頭から最初の訳の手前まで。
///
/// プレイヤーとは位置でつながっている。開くとプレイヤーで聞いていた項目から
/// 順に出題し、問題が進むたびにプレイヤーの位置も同じ項目へ動かす。
/// 閉じれば、テストで進んだ所からそのまま聞き続けられる。
struct ListeningTestView: View {
    let track: Track
    var onClose: () -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    @StateObject private var segment = SegmentPlayer()

    /// 鳴り終えてから答えを出すまでの秒数。次回も同じ値で始める。
    @AppStorage("listenTestDelay") private var delay: Double = 3
    /// 出題の順番を混ぜるか。教材の並び順で覚えてしまうのを避けたいとき用。
    /// ふだんはプレイヤーの位置から順に進めたいので、既定は混ぜない。
    @AppStorage("listenTestShuffle") private var shuffle = false

    private enum Phase: Equatable { case loading, listening, waiting, answer, finished, empty }

    @State private var cues: [SubtitleCue] = []
    @State private var groups: [SubtitleGroup] = []
    /// 出題する項目の番号の並び
    @State private var queue: [Int] = []
    /// いま queue の何番目を出しているか
    @State private var position = 0
    @State private var phase: Phase = .loading
    /// 答えを待ち始めた時刻。輪の満ち方と残り秒数はここから計る。
    @State private var waitStart = Date()
    /// いまの問題を出した時刻。直後の「覚えた」は前の問題への二度押しとみなして捨てる。
    @State private var questionStart = Date()
    /// 答えを見ずに「覚えた」を押したとき、何に印を付けたかを一瞬だけ示す
    @State private var toast: Toast?
    /// 答えの画面に出している英文と訳。答えを出した時点で控えておく。
    /// 次の問題へ進むと番号が先に変わるので、消えていく途中の答えに
    /// 次の問題の中身が一瞬映ってしまうのを防ぐ。
    @State private var shownEnglish: [String] = []
    @State private var shownJapanese: [String] = []

    private struct Toast: Equatable {
        let id = UUID()
        let text: String
    }
    /// 問題を切り替えるたびに増やす。古い問題の待ち時間や鳴り終わりを無視するため。
    @State private var token = 0
    /// この回で覚えた印を付けた数と、「まだ」にした項目
    @State private var knownCount = 0
    @State private var notYet: [Int] = []
    /// 直前に覚えた印を付けた項目。押し間違えたときに取り消せるように覚えておく。
    @State private var lastMarked: Int?
    /// この回を始めた項目。「最初からやり直す」はここから出し直す。
    @State private var sessionStart = 0

    private static let delayChoices: [Double] = [0, 1, 2, 3, 5, 8]

    private var currentGroup: SubtitleGroup? {
        guard queue.indices.contains(position), groups.indices.contains(queue[position]) else { return nil }
        return groups[queue[position]]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            progressBar
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // 答えを待っている間は、画面のどこを押しても答えを出せる
                .onTapGesture { if phase == .listening || phase == .waiting { reveal() } }
                .overlay(alignment: .top) { toastView }
            if phase != .finished && phase != .empty && phase != .loading {
                bottomButtons
            }
        }
        .foregroundStyle(.white)
        .background(NightBackdrop().ignoresSafeArea())
        // テストの間だけ暗い画面にする。時計や電池の表示も白にそろう。
        .preferredColorScheme(.dark)
        .onAppear(perform: start)
        .onDisappear {
            token += 1
            segment.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .music3xListeningTest)) { note in
            handleTestSignal(note.userInfo?["action"] as? String)
        }
    }

    // MARK: - 上の帯

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("テストを終わる")
            .accessibilityIdentifier("listeningTestClose")

            VStack(alignment: .leading, spacing: 2) {
                Text("LISTENING TEST")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Night.cyan)
                Text(track.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // プレイヤーと同じく、教材全体の何項目目かで示す
            if let group = currentGroup, phase != .finished {
                Text("\(group.id + 1) / \(groups.count)")
                    .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Menu {
                Picker("答えが出るまで", selection: $delay) {
                    ForEach(Self.delayChoices, id: \.self) { value in
                        Text(value == 0 ? "すぐ" : "\(Int(value)) 秒").tag(value)
                    }
                }
                Toggle("順番を混ぜる", isOn: $shuffle)
                Button("最初からやり直す", action: restart)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .accessibilityLabel("テストの設定")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// 教材全体のどのあたりを出しているかの細い帯。プレイヤーの再生位置と同じ物差し。
    private var progressBar: some View {
        GeometryReader { geo in
            let total = max(groups.count, 1)
            let done = phase == .finished ? total : (currentGroup.map { $0.id + 1 } ?? 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Night.cyan, Night.blue],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * CGFloat(done) / CGFloat(total), done > 0 ? 4 : 0))
                    .animation(.easeOut(duration: 0.3), value: done)
            }
        }
        .frame(height: 4)
        .opacity(queue.isEmpty ? 0 : 1)
    }

    // MARK: - 中身

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView().tint(.white)
        case .empty:
            message(icon: "checkmark.seal.fill", iconColor: Night.green,
                    title: "出せる問題がありません",
                    detail: "この音源は、ぜんぶ覚えた印が付いています。")
        case .listening, .waiting:
            listeningView
        case .answer:
            answerView
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .finished:
            finishedView
        }
    }

    /// 答えを伏せている間の画面。文字は出さず、聞いていることと残り時間だけを示す。
    private var listeningView: some View {
        VStack(spacing: 26) {
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(waitStart)
                let progress = phase == .waiting && delay > 0 ? min(max(elapsed / delay, 0), 1) : 0
                let remaining = max(0, Int((delay - elapsed).rounded(.up)))
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(colors: [Night.cyan, Night.blue, Night.violet, Night.cyan],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Night.cyan.opacity(0.6), radius: 10)
                    if phase == .listening {
                        SoundBars(time: context.date.timeIntervalSinceReferenceDate)
                    } else {
                        Text("\(remaining)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: remaining)
                    }
                }
                .frame(width: 210, height: 210)
            }

            VStack(spacing: 6) {
                Text(phase == .listening ? "LISTENING" : "THINK")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Night.cyan.opacity(0.9))
                Text(phase == .listening ? "聞いています" : "訳を思い浮かべて")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("画面をタップすると答えが出ます")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 2)
            }
        }
    }

    /// 答えの画面。英文と訳をカードに出し、もう一度聞けるようにする。
    private var answerView: some View {
        let english = shownEnglish
        let japanese = shownJapanese

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("ENGLISH")
                    ForEach(Array(english.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("訳")
                    if japanese.isEmpty {
                        Text("(訳はありません)")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        ForEach(Array(japanese.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.white.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Button {
                    replay()
                } label: {
                    Label("もう一度聞く", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Night.cyan)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(GlassCard())
            .padding(.horizontal, 18)
            .padding(.vertical, 24)
        }
        .dynamicTypeSize(settings.textSize)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(2)
            .foregroundStyle(Night.cyan.opacity(0.85))
    }

    /// 答えを見ずに「覚えた」を押したとき、何に印を付けたかを示す
    @ViewBuilder
    private var toastView: some View {
        if let toast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Night.green)
                Text("覚えた")
                    .font(.footnote.weight(.bold))
                Text(toast.text)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
            .id(toast.id)
        }
    }

    private var finishedView: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Night.cyan.opacity(0.35), .clear],
                                         center: .center, startRadius: 4, endRadius: 80))
                    .frame(width: 160, height: 160)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Night.cyan)
            }
            Text("おわり")
                .font(.system(.title, design: .rounded).weight(.bold))
            HStack(spacing: 12) {
                stat("覚えた", knownCount, Night.green)
                stat("まだ", notYet.count, Night.orange)
            }
            .padding(.horizontal, 24)
            if !notYet.isEmpty {
                Button {
                    retryNotYet()
                } label: {
                    Label("「まだ」の分をもう一度", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [Night.cyan, Night.blue],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: Night.blue.opacity(0.45), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }
            Button("終わる", action: onClose)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.vertical, 32)
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(GlassCard(cornerRadius: 22))
    }

    private func message(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(.headline, design: .rounded))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("終わる", action: onClose)
                .font(.body.weight(.semibold))
                .foregroundStyle(Night.cyan)
                .padding(.top, 8)
        }
        .padding(32)
    }

    // MARK: - 下のボタン

    /// 右はいつでも「覚えた」、左はいつでも「まだ」。答えを待たずにどちらも押せる。
    /// 聞き直したいときは、答えのカードの「もう一度聞く」を使う。
    private var bottomButtons: some View {
        VStack(spacing: 10) {
            if lastMarked != nil {
                Button {
                    undoLastMark()
                } label: {
                    Label("直前の「覚えた」を取り消す", systemImage: "arrow.uturn.backward")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                glassButton("まだ", systemImage: "arrow.right", id: "listeningTestNotYet", action: markNotYet)
                Button(action: markKnown) {
                    Label("覚えた", systemImage: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [Night.green, Night.greenDeep],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: Night.green.opacity(0.4), radius: 14, y: 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("listeningTestKnow")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func glassButton(_ title: String, systemImage: String, id: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - 進め方

    private func start() {
        guard phase == .loading else { return }
        // いつもの再生機が鳴っていたら止める。二つ同時に鳴ると聞き取れない。
        if player.isPlaying { player.pause() }

        if let url = library.subtitleURL(for: track) {
            let content = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .shiftJIS)) ?? ""
            cues = SubtitleParser.parse(content)
            groups = cues.grouped()
        }
        sessionStart = startingGroup()
        // プレイヤーに別の音源が載っていたら、この音源へ載せ替える(鳴らしはしない)。
        // テストの進み具合をプレイヤーの位置へ映すため。
        if player.currentTrackID != track.id {
            loadIntoPlayer(startAt: groups.indices.contains(sessionStart)
                           ? groups[sessionStart].start : currentTrack.lastPosition)
        }
        segment.load(url: library.audioURL(for: track))
        buildQueue(from: sessionStart)
        // 画面が開ききってから鳴らす。開く途中で鳴り出すと頭を聞き逃す。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { startQuestion() }
    }

    /// ライブラリ側の最新の音源情報(止めた位置などは開いた後にも変わる)
    private var currentTrack: Track {
        library.tracks.first(where: { $0.id == track.id }) ?? track
    }

    /// テストを始める項目。プレイヤーにこの音源が載っていればいま聞いている項目、
    /// 載っていなければ前回止めた位置の項目。
    private func startingGroup() -> Int {
        if player.currentTrackID == track.id, let index = player.activeGroupIndex,
           groups.indices.contains(index) {
            return index
        }
        let time = currentTrack.lastPosition
        return groups.group(at: time) ?? groups.firstIndex(where: { $0.start >= time }) ?? 0
    }

    private func loadIntoPlayer(startAt: Double) {
        let current = currentTrack
        player.load(
            audioURL: library.audioURL(for: current),
            subtitleURL: library.subtitleURL(for: current),
            title: current.displayName,
            trackID: current.id,
            startAt: startAt
        )
        player.applyLearned(library.learnedGroups(for: current.id, cueCount: player.cues.count))
        player.speed = settings.defaultSpeed
    }

    /// 覚えた印の付いていない、英語の部分がある項目を並べる。
    /// 順番どおりのときは start の項目から最後まで出し、そのあと先頭へ戻って手前まで出す。
    private func buildQueue(from start: Int) {
        let learned = library.learnedGroups(for: track.id, cueCount: cues.count)
        let candidates = groups.indices.filter { !learned.contains($0) && questionRange(of: groups[$0]) != nil }
        let ids = shuffle
            ? candidates.shuffled()
            : candidates.filter { $0 >= start } + candidates.filter { $0 < start }
        queue = ids
        position = 0
        knownCount = 0
        notYet = []
        lastMarked = nil
        phase = ids.isEmpty ? .empty : .listening
    }

    private func restart() {
        token += 1
        segment.stop()
        buildQueue(from: sessionStart)
        startQuestion()
    }

    /// 項目のうち、問題として鳴らす区間。頭から最初の訳の手前まで。
    private func questionRange(of group: SubtitleGroup) -> (start: Double, end: Double)? {
        var english: [SubtitleCue] = []
        for i in group.range where cues.indices.contains(i) {
            if cues[i].text.looksLikeTranslation {
                // 頭に訳が来る項目は、訳を飛ばして英語から拾う
                if english.isEmpty { continue } else { break }
            }
            english.append(cues[i])
        }
        guard let first = english.first, let last = english.last else { return nil }
        return (first.start, last.end)
    }

    private func startQuestion() {
        token += 1
        let my = token
        guard let group = currentGroup else {
            phase = queue.isEmpty ? .empty : .finished
            return
        }
        guard let range = questionRange(of: group) else {
            advance()
            return
        }
        follow(group)
        withAnimation(.easeOut(duration: 0.2)) { phase = .listening }
        questionStart = Date()
        segment.play(from: range.start, to: range.end, rate: settings.defaultSpeed) {
            guard my == token, phase == .listening else { return }
            beginWaiting(my)
        }
    }

    /// プレイヤーの位置を、いま出している問題の項目へ合わせる。
    /// 一覧の光る行もここへ動き、テストを閉じればこの項目から聞き続けられる。
    private func follow(_ group: SubtitleGroup) {
        guard player.currentTrackID == track.id else { return }
        if player.isPlaying { player.pause() }
        player.seek(to: group.start)
        library.updatePosition(group.start, for: track.id)
    }

    /// 鳴り終えた。決めた秒数だけ待ってから答えを出す。
    private func beginWaiting(_ my: Int) {
        guard delay > 0 else {
            reveal()
            return
        }
        // 輪は一定の速さで満ちていくので、残りが目で分かる(waitStart から計る)
        waitStart = Date()
        phase = .waiting
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard my == token, phase == .waiting else { return }
            reveal()
        }
    }

    private func reveal() {
        guard phase == .listening || phase == .waiting else { return }
        token += 1
        segment.stop()
        let lines = currentGroup.map { $0.lines(in: cues).map(\.text) } ?? []
        shownEnglish = lines.filter { !$0.looksLikeTranslation }
        shownJapanese = lines.filter { $0.looksLikeTranslation }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { phase = .answer }
    }

    /// 問題をもう一度鳴らす。答えを出したあとなら、答えは出したまま鳴らすだけ。
    private func replay() {
        guard let group = currentGroup, let range = questionRange(of: group) else { return }
        if phase == .answer {
            segment.play(from: range.start, to: range.end, rate: settings.defaultSpeed) {}
        } else {
            startQuestion()
        }
    }

    /// 答えが出た後はもちろん、出る前でも押せる。分かったと思ったらすぐ次へ進めるように。
    private func markKnown() {
        guard let group = currentGroup else { return }
        switch phase {
        case .answer:
            break
        case .listening, .waiting:
            // 出したばかりの問題への「覚えた」は、前の問題で押した二度押しとみなして捨てる。
            // 聞いてもいない項目に印が付くのを防ぐため。
            guard Date().timeIntervalSince(questionStart) > 0.5 else { return }
            token += 1
            segment.stop()
            showToast(for: group)
        default:
            return
        }
        setLearned(true, group: group.id)
        knownCount += 1
        lastMarked = group.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        advance()
    }

    /// 答えを見ずに印を付けた項目の英文を、上に一瞬だけ出す
    private func showToast(for group: SubtitleGroup) {
        let english = group.lines(in: cues).map(\.text).first { !$0.looksLikeTranslation } ?? ""
        let item = Toast(text: english)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { toast = item }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard toast == item else { return }
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }

    /// 答えが出た後はもちろん、出る前でも押せる。分からないと思ったらすぐ次へ。
    private func markNotYet() {
        guard let group = currentGroup else { return }
        switch phase {
        case .answer:
            break
        case .listening, .waiting:
            // 出したばかりの問題への「まだ」は、前の問題で押した二度押しとみなして捨てる
            guard Date().timeIntervalSince(questionStart) > 0.5 else { return }
            token += 1
            segment.stop()
        default:
            return
        }
        notYet.append(group.id)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        advance()
    }

    private func undoLastMark() {
        guard let group = lastMarked else { return }
        setLearned(false, group: group)
        knownCount = max(0, knownCount - 1)
        // 取り消した分は「まだ」に回し、最後の「もう一度」で出し直せるようにする
        notYet.append(group)
        lastMarked = nil
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    private func advance() {
        segment.stop()
        position += 1
        startQuestion()
    }

    private func retryNotYet() {
        var ids = notYet
        if shuffle { ids.shuffle() }
        queue = ids
        position = 0
        notYet = []
        knownCount = 0
        lastMarked = nil
        startQuestion()
    }

    /// 英→日タブと同じ覚えた印へ書く。いつもの再生機にこの音源が載っていれば、そちらにも映す。
    private func setLearned(_ learned: Bool, group: Int) {
        library.setLearned(learned, group: group, cueCount: cues.count, for: track.id)
        if player.currentTrackID == track.id {
            player.setLearned(learned, group: group)
        }
    }

    // MARK: - 検証用

    private func handleTestSignal(_ action: String?) {
        switch action {
        case "reveal": reveal()
        case "know": markKnown()
        case "notyet": markNotYet()
        case "undo": undoLastMark()
        case "close": onClose()
        case "state":
            NSLog("[TEST] listen phase=%@ muted=%@ pos=%d/%d group=%@ playerAt=%@ head=%@ tail=%@ known=%d notYet=%d learned=%@",
                  "\(phase)", String(segment.isHardMuted), position, queue.count,
                  currentGroup.map { String($0.id) } ?? "nil",
                  player.activeGroupIndex.map(String.init) ?? "nil",
                  queue.prefix(4).map(String.init).joined(separator: ","),
                  queue.suffix(3).map(String.init).joined(separator: ","),
                  knownCount, notYet.count,
                  library.learnedGroups(for: track.id, cueCount: cues.count)
                      .sorted().map(String.init).joined(separator: ","))
        default: break
        }
    }
}

extension Notification.Name {
    /// 検証用: 聞き取りテストを外から操作する合図。userInfo["action"] に操作名を入れる。
    static let music3xListeningTest = Notification.Name("music3xListeningTest")
}

// MARK: - 見た目の部品

/// 聞いている間、輪の中で揺れる音の棒
private struct SoundBars: View {
    let time: TimeInterval

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(0..<5, id: \.self) { i in
                let phase = time * 5.2 + Double(i) * 0.9
                let level = 0.35 + 0.65 * abs(sin(phase) * cos(phase * 0.43 + Double(i)))
                Capsule()
                    .fill(LinearGradient(colors: [Night.cyan, Night.blue],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 8, height: 18 + 52 * level)
            }
        }
        .frame(height: 74)
        .shadow(color: Night.cyan.opacity(0.5), radius: 8)
    }
}

