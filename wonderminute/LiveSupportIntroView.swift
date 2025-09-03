import SwiftUI
import FirebaseAuth

struct LiveSupportIntroView: View {

    
    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    // 상단 아이콘/타이틀 (참고 이미지 스타일)
                    // HERO 카드
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            // ✅ WelcomeView와 동일 스타일의 로고 카드 사용
                            AppIconCard(logoName: "AppLogo",
                                        cardSize: 56,     // 헤더용 작은 카드
                                        logoSize: 36,     // 내부 로고 크기
                                        corner: 12,
                                        glow: false)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("원더미닛 고객지원")
                                    .font(.title3.weight(.semibold))
                                Text("빠르고 친절한 1:1 실시간 상담")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }


                        // 운영시간 캡슐
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                            Text("운영시간 10:00–18:00")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Capsule())
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                    )

                    .padding(.horizontal)
                    .padding(.top, 12)

                    // 안내/주의 배너
                    VStack(alignment: .leading, spacing: 10) {
                        Text("상담 전 안내")
                            .font(.headline)
                        Text("현재 시간이 운영시간 외일 수 있으며, 영업 시간에 순차적으로 답변됩니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Divider().opacity(0.3)
                        VStack(alignment: .leading, spacing: 6) {
                            Label("불편 사항, 결제/환불, 신고/차단 등 어떤 주제든 먼저 메시지를 보내주세요.", systemImage: "paperplane.fill")
                            Label("상담사는 순서대로 확인 후 1:1 채팅방으로 연결합니다.", systemImage: "person.fill.badge.plus")
                            Label("대화 품질을 위해 기본 에티켓을 지켜주세요.", systemImage: "hand.raised.fill")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
                    .padding(.horizontal)

                    NavigationLink {
                        LiveChatSessionView()
                    } label: {
                        Text("실시간 상담 시작하기")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                // ✅ AppTheme와 동일한 브랜드 그라데이션 적용
                                LinearGradient(colors: [AppTheme.purple, AppTheme.blue],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .foregroundColor(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 8)
                    }


                    .padding(.horizontal)
                    .padding(.top, 4)

                    Text("상담 내용은 커뮤니티 가이드라인 및 약관에 따라 처리됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                }
                .padding(.bottom, 24)
            }
            .navigationTitle("상담하기")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
