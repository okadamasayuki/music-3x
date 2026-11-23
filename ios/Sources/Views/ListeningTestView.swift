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
    @AppStorage("listenTestShuffle") private var shuffle = true

    private enum Phase: Equatable { case loading, listening, waiting, answer, finished, empty }

    @State private var cues: [SubtitleCue] = []
    @State private var groups: [SubtitleGroup] = []
    /// 出題する項目の番号の並び
    @State private var queue: [Int] = []
    /// いま queue の何番目を出しているか
    @State private var position = 0
    @State private var phase: Phase = .loading
    /// 答えが出るまでの残りを示す輪の進み(0〜1)
    @State private var ringProgress: CGFloat = 0
    /// 問題を切り替えるたびに増やす。古い問題の待ち時間や鳴り終わりを無視するため。
    @State private var token = 0
    /// この回で覚えた印を付けた数と、「まだ」にした項目
    @State private var knownCount = 0
    @State private var notYet: [Int] = []
    /// 直前に覚えた印を付けた項目。押し間違えたときに取り消せるように覚えておく。
    @State private var lastMarked: Int?

    private static let delayChoices: [Double] = [0, 1, 2, 3, 5, 8]

    private var currentGroup: SubtitleGroup? {
        guard queue.indices.contains(position), groups.indices.contains(queue[position]) else { return nil }
        return groups[queue[position]]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // 答えを待っている間は、画面のどこを押しても答えを出せる
                .onTapGesture { if phase == .listening || phase == .waiting { reveal() } }
            if phase != .finished && phase != .empty && phase != .loading {
                bottomButtons
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(.systemGray6)))
            }
            .accessibilityLabel("テストを終わる")
            .accessibilityIdentifier("listeningTestClose")

            VStack(alignment: .leading, spacing: 1) {
                Text("聞き取りテスト")
                    .font(.headline)
                Text(track.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !queue.isEmpty, phase != .finished {
                Text("\(min(position + 1, queue.count)) / \(queue.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(.systemGray6)))
            }
            .accessibilityLabel("テストの設定")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - 中身

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
        case .empty:
            message(icon: "checkmark.circle.fill", iconColor: .green,
                    title: "出せる問題がありません",
                    detail: "この音源は、ぜんぶ覚えた印が付いています。")
        case .listening, .waiting:
            listeningView
        case .answer:
            answerView
        case .finished:
            finishedView
        }
    }

    /// 答えを伏せている間の画面。文字は出さず、聞いていることと残り時間だけを示す。
    private var listeningView: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: phase == .waiting ? ringProgress : 0)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: phase == .listening ? "ear.fill" : "ear")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
            }
            .frame(width: 150, height: 150)

            Text(phase == .listening ? "聞いています" : "訳を思い浮かべて")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// 答えの画面。英文と訳を出し、もう一度聞けるようにする。
    private var answerView: some View {
        let lines = currentGroup.map { $0.lines(in: cues).map(\.text) } ?? []
        let english = lines.filter { !$0.looksLikeTranslation }
        let japanese = lines.filter { $0.looksLikeTranslation }

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(english.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if japanese.isEmpty {
                        Text("(訳はありません)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(japanese.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.title3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Button {
                    replay()
                } label: {
                    Label("もう一度聞く", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .dynamicTypeSize(settings.textSize)
    }

    private var finishedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Text("おわり")
                .font(.title2.weight(.semibold))
            HStack(spacing: 28) {
                stat("覚えた", knownCount, .green)
                stat("まだ", notYet.count, .orange)
            }
            if !notYet.isEmpty {
                Button {
                    retryNotYet()
                } label: {
                    Label("「まだ」の分をもう一度", systemImage: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
            Button("終わる", action: onClose)
                .padding(.top, 4)
        }
        .padding(32)
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func message(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(iconColor)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("終わる", action: onClose)
                .padding(.top, 8)
        }
        .padding(32)
    }

    // MARK: - 下のボタン

    /// 押し間違いを避けるため、左右の役目を場面ごとにそろえてある。
    /// 「答えを見る」を二度押ししても、二度目は「まだ」に当たり、印は付かない。
    private var bottomButtons: some View {
        VStack(spacing: 8) {
            if lastMarked != nil {
                Button {
                    undoLastMark()
                } label: {
                    Text("直前の「覚えた」を取り消す")
                        .font(.footnote)
                }
            }
            HStack(spacing: 12) {
                if phase == .answer {
                    bigButton("まだ", systemImage: "arrow.right", color: Color(.systemGray5),
                              foreground: .primary, id: "listeningTestNotYet", action: markNotYet)
                    bigButton("覚えた", systemImage: "checkmark", color: .green,
                              foreground: .white, id: "listeningTestKnow", action: markKnown)
                } else {
                    bigButton("答えを見る", systemImage: "eye", color: Color(.systemGray5),
                              foreground: .primary, id: "listeningTestReveal", action: reveal)
                    bigButton("もう一度聞く", systemImage: "speaker.wave.2.fill", color: Color(.systemGray5),
                              foreground: .accentColor, id: "listeningTestReplay", action: replay)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func bigButton(_ title: String, systemImage: String, color: Color, foreground: Color,
                           id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color))
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
        segment.load(url: library.audioURL(for: track))
        buildQueue()
        // 画面が開ききってから鳴らす。開く途中で鳴り出すと頭を聞き逃す。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { startQuestion() }
    }

    /// 覚えた印の付いていない、英語の部分がある項目を並べる。
    private func buildQueue() {
        let learned = library.learnedGroups(for: track.id, cueCount: cues.count)
        var ids = groups.indices.filter { !learned.contains($0) && questionRange(of: groups[$0]) != nil }
        if shuffle { ids.shuffle() }
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
        buildQueue()
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
        phase = .listening
        ringProgress = 0
        segment.play(from: range.start, to: range.end, rate: settings.defaultSpeed) {
            guard my == token, phase == .listening else { return }
            beginWaiting(my)
        }
    }

    /// 鳴り終えた。決めた秒数だけ待ってから答えを出す。
    private func beginWaiting(_ my: Int) {
        guard delay > 0 else {
            reveal()
            return
        }
        phase = .waiting
        ringProgress = 0
        // 輪は一定の速さで満ちていくので、残りが目で分かる
        DispatchQueue.main.async {
            withAnimation(.linear(duration: delay)) { ringProgress = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard my == token, phase == .waiting else { return }
            reveal()
        }
    }

    private func reveal() {
        guard phase == .listening || phase == .waiting else { return }
        token += 1
        segment.stop()
        phase = .answer
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

    private func markKnown() {
        guard phase == .answer, let group = currentGroup else { return }
        setLearned(true, group: group.id)
        knownCount += 1
        lastMarked = group.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        advance()
    }

    private func markNotYet() {
        guard phase == .answer, let group = currentGroup else { return }
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
            NSLog("[TEST] listen phase=%@ pos=%d/%d group=%@ known=%d notYet=%d learned=%@",
                  "\(phase)", position, queue.count,
                  currentGroup.map { String($0.id) } ?? "nil",
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
