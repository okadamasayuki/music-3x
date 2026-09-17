import SwiftUI

/// 「単語」タブ。端末内の単語帳を一覧し、選ぶと(RootView のオーバーレイで)プレイヤーを開く。
struct WordDeckListView: View {
    @EnvironmentObject private var store: WordDeckStore
    /// デッキを開く。実体は RootView 側のオーバーレイ表示(本来のプレイヤーと同じ流儀)。
    var onOpen: (String) -> Void

    var body: some View {
        Group {
            if store.decks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("単語帳がありません").font(.headline)
                    Text("Documents/WordDecks/ に単語帳(words.json と audio/)を入れると、ここに出ます。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.decks) { deck in
                    Button {
                        onOpen(deck.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deck.name).font(.headline)
                                Text("\(deck.words.count) 語")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("単語")
        .onAppear { store.refresh() }
    }
}
