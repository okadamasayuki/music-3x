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

    /// 入力欄の下書き。アプリが途中で落ちても書きかけが消えないよう、
    /// 端末に置いて、書くたび・聞き取るたびに保存する。
    @AppStorage("improveDraft") private var draft = ""
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
            if !store.items.isEmpty { pendingSection }
        }
        .listStyle(.insetGrouped)
        // 入力欄の外を触るかスクロールしたら、キーボードを下げて一覧を見せる
        .dismissKeyboardOnTap()
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("改善")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { checkReachability() }
        // 他のタブや画面を見に行っても書き取りは止めない。アプリの外へ
        // 出ても続けるのと同じ理由で、調べ物を挟む長い口述のため。
        // 止まるのは完了ボタンを押したときだけ。
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
        // 声で入れたメモは数行になりがちで、アラートの1行欄では直しづらい。
        // 全体を見渡しながら書き直せる広い欄をシートで出す。
        .sheet(item: $editTarget) { _ in
            editSheet
        }
    }

    // MARK: - 編集

    @FocusState private var editFocused: Bool

    private var editSheet: some View {
        NavigationStack {
            TextEditor(text: $editText)
                .focused($editFocused)
                .padding(.horizontal, 12)
                .navigationTitle("内容を編集")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { editTarget = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if let target = editTarget { store.update(target.id, text: editText) }
                            editTarget = nil
                        }
                        .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveImprovementEdit")
                    }
                }
                .onAppear {
                    // 開いたらすぐ書き直せるようにする。出た直後は焦点が入らないことがあるので一拍置く
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editFocused = true }
                }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 入力

    private var inputSection: some View {
        Section {
            if dictation.isRecording {
                // 聞き取り中は流れが見えることが何より大事。TextField は文が
                // 増えても勝手に最後まで送られず、長い口述では今どこまで
                // 拾えているのか分からなくなる。聞き取り中だけ読み専用の
                // 眺めに切り替え、常にいちばん新しい行を見せておく。
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(draft.isEmpty ? "聞き取った文がここに出ます" : draft)
                            .foregroundStyle(draft.isEmpty ? Color.secondary : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                            .id("dictationTail")
                    }
                    // ふだんの入力欄(3 行ほど)と同じ背丈に合わせる。
                    // 録音に切り替わった途端に欄がぐっと伸びるのは落ち着かない
                    // という求め。最新の行へ送り続けるので、この高さで足りる。
                    .frame(height: 72)
                    .onChange(of: draft) { _ in
                        proxy.scrollTo("dictationTail", anchor: .bottom)
                    }
                    .onAppear { proxy.scrollTo("dictationTail", anchor: .bottom) }
                }
                .accessibilityIdentifier("dictationLive")
            } else {
                TextField("思いついた改善を書き留める", text: $draft, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("improvementDraft")
            }

            // 場所さえ分かれば説明の文字は要らないので、マイクの絵だけの
            // 小さなボタンにする。「追加」より控えめな大きさに留める。
            HStack(spacing: 12) {
                Button(action: toggleDictation) {
                    Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 30, minHeight: 20)
                }
                .buttonStyle(.borderedProminent)
                .tint(dictation.isRecording ? (dictation.isSuspended ? .orange : .red) : .accentColor)
                .accessibilityLabel(dictation.isRecording ? "聞き取り中。タップで完了" : "声で書き取る")
                .accessibilityIdentifier("dictationToggle")

                Spacer()

                // 言い直したくなったときに、書きかけを一息で捨てる。
                if !draft.isEmpty {
                    Button(action: clearDraft) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 30, minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("書きかけを全部消す")
                    .accessibilityIdentifier("clearDraft")
                }

                Button("追加", action: addDraft)
                    .buttonStyle(.bordered)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 28)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("addImprovement")
            }

            // 聞き取り中の案内は出さない(赤いマイクで足りるという求め)。
            // 途切れている間だけは、黙って待つと壊れて見えるので言葉で添える。
            if dictation.isRecording, dictation.isSuspended {
                Text("電話などでいったん途切れています。マイクが空きしだい続きを聞き取ります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let problem = dictation.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            // 電話などでマイクを失っている間、無言で待つと壊れたように
            // 見える。文が残っていることと、勝手に続きが始まることを添える。
            if dictation.isSuspended {
                Text("マイクをほかに取られています。空きしだい続きを聞き取ります。ここまでの文は残っています。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            Button("再接続") { checkReachability() }
                .font(.footnote)
        }
        .font(.footnote)
    }

    private var connectionLabel: String {
        switch reachable {
        // 使い方の説明はもう添えない。毎日目にする場所なので短いほどいい。
        case true: return "Mac 接続済み"
        case false: return "Mac が見つかりません"
        default: return "Mac を探しています…"
        }
    }

    // MARK: - まだ送っていない項目

    private var pendingSection: some View {
        Section("これから") {
            ForEach(store.items) { item in
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

    // MARK: - 操作

    private func toggleDictation() {
        if dictation.isRecording {
            dictation.stop()
            // 表示は途中経過の流し込みに任せているが、別のタブに居た間は
            // 流し込みが届いていない。最後の全文をここで写し取る。
            syncDraftFromDictation()
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

    /// 書きかけを全部捨てる。聞き取りの最中なら、聞き取りは続けたまま
    /// 文だけを空にして、言い直しにすぐ入れるようにする。
    private func clearDraft() {
        draft = ""
        dictationBase = ""
        dictation.clearText()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// 聞き取れている全文を下書きへ写す。
    private func syncDraftFromDictation() {
        let text = dictation.transcript
        guard !text.isEmpty else { return }
        draft = dictationBase.isEmpty ? text : dictationBase + "\n" + text
    }

    private func addDraft() {
        stopDictationIfNeeded()
        syncDraftFromDictation()
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
                // 送れた項目はその場で消す。実装の済んだものを一覧に
                // 残さない、という求めによる。届いた控えは Mac 側にある。
                store.remove(item.id)
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
}
