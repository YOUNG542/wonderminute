import SwiftUI

struct ReportedUsersMonitorView: View {
    enum Tab: String, CaseIterable {
        case queue = "대기"
        case reviewing = "검토중"
        case actioned = "조치완료"
        case dismissed = "보류/기각"
    }

    @State private var selectedTab: Tab = .queue
    @State private var searchText: String = ""
    @State private var selectedType: String = "전체" // 폭언/혐오, 성적, 사기, 스팸, 미성년, 기타…
    @State private var onlyRepeatOffenders = false

    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()
            VStack(spacing: 12) {
                // 상단 필터
                filterBar

                // 탭
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // 리스트 (샘플 placeholder)
                List {
                    Section(header: Text("\(selectedTab.rawValue) · 최근 신고")) {
                        ForEach(0..<8, id: \.self) { i in
                            NavigationLink {
                                ReportCaseDetailPlaceholder()
                            } label: {
                                HStack(spacing: 12) {
                                    Circle().fill(Color.orange.opacity(0.2)).frame(width: 36, height: 36)
                                        .overlay(Text("R").font(.footnote.bold()))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("reportedUid_\(i)")
                                            .font(.subheadline).bold()
                                        Text("유형: 폭언/혐오  • 최근 48시간 내 신고 3건")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("큐 대기")
                                        .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Color.yellow.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("신고 모니터링")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            TextField("UID/닉네임/메모 검색", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Menu(selectedType) {
                Button("전체") { selectedType = "전체" }
                Button("폭언/혐오") { selectedType = "폭언/혐오" }
                Button("성적") { selectedType = "성적" }
                Button("불법/사기") { selectedType = "불법/사기" }
                Button("스팸/광고") { selectedType = "스팸/광고" }
                Button("미성년 의심") { selectedType = "미성년 의심" }
                Button("기타") { selectedType = "기타" }
            }
            .buttonStyle(.borderedProminent)

            Toggle("상습만", isOn: $onlyRepeatOffenders)
                .toggleStyle(.switch)
        }
        .padding(.horizontal)
    }
}

private struct ReportCaseDetailPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("신고 상세 (샘플)")
                        .font(.title3.bold())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("신고된 UID: reportedUid_xxx")
                            Text("누적 신고: 5건 / 최근 7일 3건")
                            Text("최근 사유: 폭언/혐오")
                            Text("증거자료: 통화 로그/채팅 일부 (추후 표시)")
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("운영 메모").font(.headline)
                            Text("— 여기에 운영자 메모/조치 이력 표시 예정")
                                .foregroundStyle(.secondary)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("가능한 조치").font(.headline)
                            Text("• 경고 푸시/팝업\n• 일시 차단(매칭 제한)\n• 영구 정지\n• 보류/기각")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu("조치") {
                        Button("경고") {}
                        Button("임시 정지(24h)") {}
                        Button("임시 정지(7d)") {}
                        Button("영구 정지") {}
                        Divider()
                        Button("보류/기각") {}
                    }
                }
            }
        }
        .navigationTitle("신고 상세")
        .navigationBarTitleDisplayMode(.inline)
    }
}
