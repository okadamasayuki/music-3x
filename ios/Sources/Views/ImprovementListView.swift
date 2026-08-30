import PhotosUI
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
    /// Claude Code からの対応結果。Mac 側がファイルを置き、ここで読む。
    @StateObject private var resultStore = ImprovementResultStore()

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
    /// Mac の受け口に届くか。nil はまだ一度も調べていない。
    /// 調べ直している間も前の値を保つ。表示の幅が変わると、右上の
    /// 表示に押されてタイトルが動いて見えるため。
    @State private var reachable: Bool?
    /// 再接続の矢印の回転角。押すたびに一回転させ、押せたことを見せる。
    @State private var spinAngle = 0.0
    /// 下書きに付ける添付(保存済みのファイル名)。
    @State private var draftAttachments: [String] = []
    /// フォトピッカーの選択。取り込んだら空に戻す。
    @State private var pickedItems: [PhotosPickerItem] = []
    /// 全文表示する対応結果。
    @State private var resultDetail: ImprovementResult?
    /// 「対応済み」を全消去する前の確認。
    @State private var showClearResultsConfirm = false
    /// 書き取りのために再生を止めたか。終わったら黙って再開する。
    @State private var pausedPlayerForDictation = false

    var body: some View {
        listContent.tightTop()
    }

    private var listContent: some View {
        List {
            inputSection
            if !store.items.isEmpty { pendingSection }
            if !resultStore.results.isEmpty { resultsSection }
        }
        // 対応済みは Mac 側がファイルを置く形なので、引っ張れば読み直せる
        .refreshable { resultStore.reload() }
        .listStyle(.insetGrouped)
        // 入力欄の外を触るかスクロールしたら、キーボードを下げて一覧を見せる
        .dismissKeyboardOnTap()
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("改善")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                connectionStatus
            }
        }
        .onAppear {
            checkReachability()
            resultStore.reload()
        }
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
        // 対応済みの全消去は確認してから。まとめて消える操作なので。
        .alert("対応済みをすべて消しますか?", isPresented: $showClearResultsConfirm) {
            Button("キャンセル", role: .cancel) {}
            Button("すべて消す", role: .destructive) { resultStore.removeAll() }
        } message: {
            Text("対応済み \(resultStore.results.count) 件をまとめて消します。")
        }
        // 声で入れたメモは数行になりがちで、アラートの1行欄では直しづらい。
        // 全体を見渡しながら書き直せる広い欄をシートで出す。
        .sheet(item: $editTarget) { _ in
            editSheet
        }
        // 対応結果の全文。3 行の抜粋では原因の説明まで読めない。
        .sheet(item: $resultDetail) { result in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(result.title)
                            .font(.headline)
                        Text(result.summary)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                }
                .navigationTitle("対応内容")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { resultDetail = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
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
            // 入力欄はひとつだけ置き、聞き取り中はその上へ読み専用の眺めを
            // 重ねる。欄の背丈は常に下の TextField が決めるので、録音へ
            // 切り替えた瞬間に欄の大きさは 1pt も変わらない。文が伸びた
            // ときの育ち方も、手で打っているときとまったく同じになる。
            // 空欄への誘い文句は置かない。毎日使う本人には言わずもがなで、
            // 目に入るたびに読まされるだけだという求めによる。
            TextField("", text: $draft, axis: .vertical)
                .lineLimit(3...8)
                .disabled(dictation.isRecording)
                .opacity(dictation.isRecording ? 0 : 1)
                .accessibilityIdentifier("improvementDraft")
                .overlay {
                    if dictation.isRecording {
                        // 聞き取り中は流れが見えることが何より大事。TextField は
                        // 文が増えても勝手に最後まで送られないので、常に最新の
                        // 行が見える眺めをかぶせる。
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                Text(draft)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("dictationTail")
                            }
                            .onChange(of: draft) { _ in
                                proxy.scrollTo("dictationTail", anchor: .bottom)
                            }
                            .onAppear { proxy.scrollTo("dictationTail", anchor: .bottom) }
                        }
                        .accessibilityIdentifier("dictationLive")
                    }
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

                // 画面の様子を見せたいときのための、写真・動画の添付
                PhotosPicker(selection: $pickedItems, maxSelectionCount: 15,
                             matching: .any(of: [.images, .videos])) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 30, minHeight: 20)
                }
                .buttonStyle(.bordered)
                .onChange(of: pickedItems) { items in
                    Task { await importPicked(items) }
                }
                .accessibilityIdentifier("attachPicker")

                if !draftAttachments.isEmpty {
                    Text("📎\(draftAttachments.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

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
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && draftAttachments.isEmpty)
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
        }
    }

    /// Mac に届くかどうかの表示。家に帰って Mac を点けたらここが緑になる。
    /// 画面の右上に置き、押せばそのまま再接続になる。入力欄の近くに
    /// 並べると毎回目に入って邪魔だという求めで、隅へ寄せた。
    private var connectionStatus: some View {
        Button {
            // 回すのは押したときだけ。タブを開き直したときの自動の確かめ
            // でも回ると、勝手に何かが動いたように見えて落ち着かない。
            withAnimation(.linear(duration: 0.7)) { spinAngle += 360 }
            checkReachability()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(reachable == true ? Color.green : reachable == false ? Color.orange : Color.gray)
                    .frame(width: 8, height: 8)
                Text(connectionLabel)
                    .font(.footnote)
                Image(systemName: "arrow.clockwise")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(spinAngle))
            }
            .foregroundStyle(.secondary)
            // 端に張り付くと窮屈なので、両側に一息ぶんの余白を取る
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(connectionLabel)。タップで再接続")
        .accessibilityIdentifier("connectionStatus")
    }

    private var connectionLabel: String {
        switch reachable {
        // 相手が Mac なのは言わずもがな。毎日目にする場所なので短いほどいい。
        case true: return "接続済み"
        case false: return "未接続"
        default: return "確認中…"
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
                HStack(spacing: 6) {
                    Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                    if let count = item.attachments?.count, count > 0 {
                        Text("📎\(count)")
                    }
                }
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

    // MARK: - 対応済み(Claude Code からの結果報告)

    private var resultsSection: some View {
        Section {
            ForEach(resultStore.results) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                    Text(result.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text(result.completedAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { resultDetail = result }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        resultStore.remove(result.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        } header: {
            // 見出しの右端に全消去。まとめて消える操作なので、押したら確認を挟む
            HStack {
                Text("対応済み")
                Spacer()
                Button("全消去") { showClearResultsConfirm = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .textCase(nil)
            }
        }
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
            // 教材が鳴っていたら黙らせておく。エコー消去はあるが、倍速の English を
            // 浴びせながらの日本語の書き取りは聞き違いが増える。終わったら再開する。
            if player.isPlaying {
                player.pause()
                pausedPlayerForDictation = true
            }
            dictationBase = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            dictation.start()
        }
    }

    private func stopDictationIfNeeded() {
        if dictation.isRecording { dictation.stop() }
    }

    /// 書き取りが終わったら、マイクを元の役目へ返し、止めていた再生を戻す。
    private func restoreAudio() {
        if settings.voiceControl {
            voice.start()
        } else {
            // 録音のために変えた音の設定を、再生だけの形へ戻す
            player.configureAudioSession()
        }
        if pausedPlayerForDictation {
            pausedPlayerForDictation = false
            player.play()
        }
    }

    /// 書きかけを全部捨てる。聞き取りの最中なら、聞き取りは続けたまま
    /// 文だけを空にして、言い直しにすぐ入れるようにする。
    private func clearDraft() {
        draft = ""
        dictationBase = ""
        for name in draftAttachments {
            try? FileManager.default.removeItem(
                at: ImprovementStore.mediaDir.appendingPathComponent(name))
        }
        draftAttachments = []
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
        store.add(draft, attachments: draftAttachments.isEmpty ? nil : draftAttachments)
        draft = ""
        dictationBase = ""
        draftAttachments = []
        pickedItems = []
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// フォトピッカーの選択を添付の置き場へ取り込む。
    private func importPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            // 極端に大きい動画は、送るときに待ちきれないので断る
            guard data.count < 120_000_000 else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
            let name = "\(UUID().uuidString).\(ext)"
            try? data.write(to: ImprovementStore.mediaDir.appendingPathComponent(name))
            draftAttachments.append(name)
        }
        pickedItems = []
        if !draftAttachments.isEmpty {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
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

    /// 静かに調べ直す。文言を「探しています…」へ入れ替える形にしないのは、
    /// 幅が変わってタイトルまで動いて見えるため。結果だけを色と言葉に映す。
    private func checkReachability() {
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
