import SwiftUI

struct SuspendedGateView: View {
    let m: ModerationState

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .gray.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52, weight: .bold))
                    .padding(.top, 24)

                Text("접근이 제한되었습니다")
                    .font(.title2.bold())

                // 사유
                VStack(spacing: 6) {
                    Text("사유").font(.caption).foregroundStyle(.secondary)
                    Text(m.humanReason).font(.headline)
                }

                // 범위
                
                VStack(spacing: 6) {
                    Text("제한 범위").font(.caption).foregroundStyle(.secondary)
                    Text("앱 내 모든 서비스").font(.subheadline)   // ← 고정 문구
                }


                // 기간/남은 시간
                VStack(spacing: 6) {
                    Text("기간").font(.caption).foregroundStyle(.secondary)
                    Text(m.remainingText).font(.subheadline)
                }

                // 가이드
                Text("운영자 제재로 인해 현재 서비스 이용이 제한되었습니다.\n자세한 안내는 공지 및 약관을 참고해 주세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

      
            // 액션 버튼들 (이의제기 제거)
                VStack(spacing: 10) {
                    Button {
                        // 약관/정책 링크 (교체)
                        if let url = URL(string: "https://wonderminute.app/policy") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("정책/가이드 확인")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                Spacer()
            }
            .foregroundColor(.white)
            .padding()
        }
    }
}

// 간단한 태그 래핑용
private struct FlowWrap<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    init(_ items: [String], @ViewBuilder content: @escaping (String) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        var totalWidth = CGFloat.zero
        var rows: [[String]] = [[]]

        // 아주 간단한 래핑(대충 나눔)
        let maxWidth = UIScreen.main.bounds.width - 48
        for item in items {
            let w = (item.count <= 4 ? 60 : CGFloat(item.count * 10))
            if totalWidth + w > maxWidth {
                rows.append([item])
                totalWidth = w
            } else {
                rows[rows.count - 1].append(item)
                totalWidth += w
            }
        }

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<rows.count, id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(rows[i], id: \.self) { s in content(s) }
                }
            }
        }
    }
}
