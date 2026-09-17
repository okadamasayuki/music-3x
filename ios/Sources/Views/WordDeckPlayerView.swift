import SwiftUI

/// 単語列プレイヤー画面。今の単語を大きく出し、英→日→英などの順で流す。
/// RootView のオーバーレイに載せて表示する(本来のプレイヤーと同じ流儀)。
/// 右へなぞる/左上「⌄」で一覧へ戻る。
struct WordDeckPlayerView: View {
    let deck: WordDeck
    var onClose: () -> Void
    var onBackDragChanged: (CGFloat) -> Void
    var onBackDragEnded: (CGFloat, CGFloat) -> Void

    @EnvironmentObject private var player: WordDeckPlayer
    @State private var showSettings = false

    private var card: WordCard? { player.currentCard }

    var body: some View {
        VStack(spacing: 0) {
            header

            // 一覧を全画面に。操作ボタンは下へ。
            wordList.frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 40) {
                Button { player.prevWord() } label: { Image(systemName: "backward.end.fill").font(.title2) }
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }
                Button { player.nextWord() } label: { Image(systemName: "forward.end.fill").font(.title2) }
            }
            .padding(.top, 8).padding(.bottom, 6)
        }
        // 画面のどこを右へなぞっても戻れるよう、全面を判定対象にする(Spacer は素だと拾わない)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
        .sheet(isPresented: $showSettings) { WordDeckSettingsView().presentationDetents([.medium, .large]) }
        .onAppear { if player.deck?.id != deck.id { player.load(deck) } }
    }

    private var header: some View {
        ZStack {
            Text(deck.name).font(.headline).lineLimit(1)
            HStack {
                Button { onClose() } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color(.systemGray6)))
                }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color(.systemGray6)))
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private var wordList: some View {
        ScrollViewReader { proxy in
            List(0..<deck.words.count, id: \.self) { i in
                row(i)
            }
            .listStyle(.plain)
            .onChange(of: player.index) { new in
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
            // 一覧の上を右へなぞっても戻れるようにする(縦スクロールとは両立)
            .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
        }
    }

    @ViewBuilder
    private func row(_ i: Int) -> some View {
        let w = deck.words[i]
        let active = (i == player.index)
        let done = player.isLearned(w.num)
        HStack(spacing: 12) {
            Button { player.toggleLearned(w.num) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(done ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            Button {
                player.jump(to: i)
                if !player.isPlaying { player.play() }
            } label: {
                HStack {
                    Text(w.en).fontWeight(active ? .bold : .regular)
                    Spacer()
                    Text(w.ja).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .opacity(done ? 0.4 : 1)
            }
            .buttonStyle(.plain)
        }
        .id(i)
        .listRowBackground(active ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

/// 再生順・間・速さ・リピートの設定シート。
struct WordDeckSettingsView: View {
    @EnvironmentObject private var player: WordDeckPlayer
    @Environment(\.dismiss) private var dismiss

    private let presets: [(String, [String])] = [
        ("英 → 日 → 英", ["en", "ja", "en"]),
        ("英 → 日", ["en", "ja"]),
        ("英 → 日 → 英 → 英", ["en", "ja", "en", "en"]),
        ("日 → 英", ["ja", "en"]),
        ("英のみ", ["en"]),
        ("日のみ", ["ja"]),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("再生順") {
                    ForEach(presets, id: \.0) { name, seq in
                        Button {
                            player.order = seq
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if player.order == seq { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("間(ま)") {
                    HStack { Text("語の中"); Spacer(); Text(String(format: "%.2f 秒", player.gap)) }
                    Slider(value: $player.gap, in: 0...1.5, step: 0.05)
                    HStack { Text("次の単語まで"); Spacer(); Text(String(format: "%.2f 秒", player.wordGap)) }
                    Slider(value: $player.wordGap, in: 0...2.0, step: 0.05)
                }
                Section("速さ") {
                    HStack { Text("再生速度"); Spacer(); Text(String(format: "%.2f 倍", player.speed)) }
                    Slider(value: $player.speed, in: 0.5...2.0, step: 0.05)
                }
                Section {
                    Toggle("覚えた単語を飛ばす", isOn: $player.skipLearned)
                    Toggle("最後まで行ったら先頭へ戻す", isOn: $player.loop)
                }
            }
            .navigationTitle("再生の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
        }
    }
}
