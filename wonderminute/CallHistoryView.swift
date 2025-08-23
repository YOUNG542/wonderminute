import SwiftUI

struct CallHistoryView: View {
    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()

            // 최소한의 플레이스홀더 리스트
            List {
                Section(header: Text("최근 통화").font(.headline)) {
                    ForEach(0..<8, id: \.self) { i in
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("상대방 \(i + 1)")
                                    .font(.subheadline).bold()
                                Text("어제 · 03:2\(i) · 2분 1\(i)초")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .scrollContentBackground(.hidden) // 리스트 배경 투명
            .background(Color.clear)
            .navigationTitle("통화 내역")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if DEBUG
struct CallHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { CallHistoryView() }
    }
}
#endif
