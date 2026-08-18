import SwiftUI
import UIKit

/// アプリ自体の改善点を書き留めておくタブ。
///
/// 出先で思いついたことを声で放り込んでおき、家に帰って Mac が点いているときに
/// 項目を左から右へスワイプすると、Mac 側で Claude Code が立ち上がって
/// その要望の実装を始める。書き取りは声が基本だが、キーボードでも書ける。
struct ImprovementListView: View {
    @EnvironmentObject private var store: ImprovementStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var voice: VoiceCommands
    @StateObject private var dictation = Dictation()

    /// 入力欄の下書き。
    @State private var draft = ""
    /// 書き取りを始めたときに入力欄へすでにあった文。聞き取りはこの後ろへ足す。
    @State private var dictationBase = ""
    /// いま Mac へ送っている最中の項目。行に回転を出して二度押しを防ぐ。
    @State private var sendingIDs: Set<UUID> = []
    /// 送れなかったときの説明。
    @State private var errorMessage: String?
    /// 編集中の項目。
    @State private var editTarget: Improvement?
    @State private var editText = ""
    /// Mac の受け口に届くか。nil はまだ調べていない。
    @State private var reachable: Bool?

    var body: some View {
        List {
            inputSection
            if !store.pending.isEmpty { pendingSection }
            if !store.sent.isEmpty { sentSection }
        }
        .listStyle(.insetGrouped)
        // 入力欄の外を触るかスクロールしたら、キーボードを下げて一覧を見せる
        .dismissKeyboardOnTap()
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("改善")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { checkReachability() }
        .onDisappear { stopDictationIfNeeded() }
        // 聞き取りの途中経過を入力欄へ流し込む。手で書いた分の後ろに足す。
        .onReceive(dictation.$transcript) { text in
            guard !text.isEmpty else { return }
            draft = dictationBase.isEmpty ? text : dictationBase + "\n" + text
        }
        // 黙っても書き取りは続く。終わるのは完了ボタンを押したときと、
        // マイクが不調で続けられなくなったとき。どちらもマイクを元の役目へ返す。
        .onChange(of: dictation.isRecording) { recording in
            if !recording { restoreAudio() }
        }
        .alert("送れませんでした", isPresented: showErrorBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("内容を編集", isPresented: showEditBinding) {
            TextField("内容", text: $editText, axis: .vertical)
            Button("キャンセル", role: .cancel) { editTarget = nil }
            Button("保存") {
                if let target = editTarget { store.update(target.id, text: editText) }
                editTarget = nil
            }
        }
    }

    // MARK: - 入力

    private var inputSection: some View {
        Section {
            TextField("思いついた改善を書き留める", text: $draft, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityIdentifier("improvementDraft")

            // 場所さえ分かれば説明の文字は要らないので、マイクの絵だけの
            // 小さなボタンにする。「追加」より控えめな大きさに留める。
            HStack(spacing: 12) {
                Button(action: toggleDictation) {
                    Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 30, minHeight: 20)
                }
                .buttonStyle(.borderedProminent)
                .tint(dictation.isRecording ? .red : .accentColor)
                .accessibilityLabel(dictation.isRecording ? "聞き取り中。タップで完了" : "声で書き取る")
                .accessibilityIdentifier("dictationToggle")

                Spacer()

                Button("追加", action: addDraft)
                    .buttonStyle(.bordered)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 28)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("addImprovement")
            }

            if let problem = dictation.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } footer: {
            connectionFooter
        }
    }

    /// Mac に届くかどうかの表示。家に帰って Mac を点けたらここが緑になる。
    private var connectionFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(reachable == true ? Color.green : reachable == false ? Color.orange : Color.gray)
                .frame(width: 8, height: 8)
            Text(connectionLabel)
            Spacer()
            Button("確かめ直す") { checkReachability() }
                .font(.footnote)
        }
        .font(.footnote)
    }

    private var connectionLabel: String {
        switch reachable {
        case true: return "Mac につながっています。左から右へスワイプで実装が始まります。"
        case false: return "Mac が見つかりません。家の Wi-Fi で Mac が起きていれば届きます。"
        default: return "Mac を探しています…"
        }
    }

    // MARK: - まだ送っていない項目

    private var pendingSection: some View {
        Section("これから") {
            ForEach(store.pending) { item in
                pendingRow(item)
            }
        }
    }

    private func pendingRow(_ item: Improvement) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if sendingIDs.contains(item.id) {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
        // 行を押したら書き直せる。聞き取りの間違いをここで直す。
        .onTapGesture {
            editText = item.text
            editTarget = item
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                send(item)
            } label: {
                Label("実装", systemImage: "hammer.fill")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.remove(item.id)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("pendingImprovement")
    }

    // MARK: - 送信済みの項目

    private var sentSection: some View {
        Section("実装へ送った項目") {
            ForEach(store.sent) { item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text)
                            .foregroundStyle(.secondary)
                        if let sentAt = item.sentAt {
                            Text("送信 \(sentAt, format: .dateTime.month().day().hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if sendingIDs.contains(item.id) {
                        ProgressView()
                    }
                }
                // うまく実装されなかったときに、同じ要望をもう一度送れるようにしておく
                .swipeActions(edge: .leading) {
                    Button {
                        send(item)
                    } label: {
                        Label("もう一度", systemImage: "arrow.counterclockwise")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.remove(item.id)
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - 操作

    private func toggleDictation() {
        if dictation.isRecording {
            dictation.stop()
        } else {
            // マイクは一つ。覚えた印の聞き役が動いていたら、書き取りの間だけ譲ってもらう
            voice.stop()
            dictationBase = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            dictation.start()
        }
    }

    private func stopDictationIfNeeded() {
        if dictation.isRecording { dictation.stop() }
    }

    /// 書き取りが終わったら、マイクを元の役目へ返す。
    private func restoreAudio() {
        if settings.voiceControl {
            voice.start()
        } else {
            // 録音のために変えた音の設定を、再生だけの形へ戻す
            player.configureAudioSession()
        }
    }

    private func addDraft() {
        stopDictationIfNeeded()
        store.add(draft)
        draft = ""
        dictationBase = ""
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func send(_ item: Improvement) {
        guard !sendingIDs.contains(item.id) else { return }
        sendingIDs.insert(item.id)
        let host = settings.improveHost
        Task { @MainActor in
            do {
                try await MacLink.send(item, host: host)
                store.markSent(item.id)
                reachable = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                errorMessage = error.localizedDescription
                reachable = false
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            sendingIDs.remove(item.id)
        }
    }

    private func checkReachability() {
        reachable = nil
        let host = settings.improveHost
        Task { @MainActor in
            reachable = await MacLink.ping(host: host)
        }
    }

    // MARK: - アラートの開閉

    private var showErrorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    private var showEditBinding: Binding<Bool> {
        Binding(get: { editTarget != nil }, set: { if !$0 { editTarget = nil } })
    }
}
