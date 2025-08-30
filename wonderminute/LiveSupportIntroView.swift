import SwiftUI
import FirebaseAuth

struct LiveSupportIntroView: View {
    @State private var agree = false
    @State private var topic: String = ""
    @State private var goChat = false
    
    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    // 상단 아이콘/타이틀 (참고 이미지 스타일)
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 36, weight: .bold))
                            .padding(12)
                            .background(Color.white.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading) {
                            Text("원더미닛 고객지원")
                                .font(.title3).bold()
                            Button("운영시간 보기") {
                                // 필요 시 다른 화면으로 이동
                            }.font(.footnote)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    
                    // 안내 카드
                    VStack(alignment: .leading, spacing: 8) {
                        Text("안녕하세요.\n원더미닛 고객지원팀입니다 😄")
                        Text("궁금한 점/불편한 점을 메시지로 보내주세요.")
                        Text("현재는 상담 운영시간이 아닐 수 있어요. 영업 시간에 순차 답변됩니다.")
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    
                    // 동의 + (선택) 주제
                    Toggle(isOn: $agree) {
                        Text("상담 기록 저장(문제 해결/운영 개선 목적)에 동의합니다.")
                    }
                    .padding(.horizontal)
                    
                    TextField("문의 주제를 간단히 적어주세요 (선택)", text: $topic)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    // 시작 버튼
                    NavigationLink(isActive: $goChat) {
                        LiveChatSessionView()
                    } label: {
                        Text("문의하기")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(agree ? Color.accentColor : Color.gray.opacity(0.4))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                    }
                    .disabled(!agree)
                    
                    Text("오전 10:00부터 운영해요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("상담하기")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
