import SwiftUI

struct ChatListView: View {
    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()

            List {
                Section(header: Text("최근 채팅").font(.headline)) {
                    ForEach(0..<10, id: \.self) { i in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.blue.opacity(0.85))
                                .frame(width: 36, height: 36)
                                .overlay(Text("\(i+1)").font(.footnote.bold()).foregroundColor(.white))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("상대방 \(i + 1)")
                                    .font(.subheadline).bold()
                                Text("마지막 메시지 미리보기…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("오전 11:\(i)0")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("채팅")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if DEBUG
struct ChatListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { ChatListView() }
    }
}
#endif
