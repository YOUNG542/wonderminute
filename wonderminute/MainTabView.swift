import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore

enum RootTab: Hashable {
    case call, history, chat, profile
}

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: RootTab = .call

    // ⬇️ 통화 모달 가드
    @State private var isCallPresented = false
    @State private var presentedForRoom: String?

    // ⬇️ 엔진/워처를 루트에서 소유
    @StateObject private var callEngine: CallEngine
    @StateObject private var matchWatcher: MatchWatcher

    init() {
        // TabBar 투명 설정
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        // 단일 엔진 인스턴스 생성
        let engine = CallEngine()
        _callEngine   = StateObject(wrappedValue: engine)
        _matchWatcher = StateObject(wrappedValue: MatchWatcher(call: engine))
    }

    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()

            TabView(selection: $selection) {
                CallView(call: callEngine, watcher: matchWatcher)
                    .tag(RootTab.call)
                    .tabItem { EmptyView() }

                CallHistoryView()
                    .tag(RootTab.history)
                    .tabItem { EmptyView() }

                ChatListView()
                    .tag(RootTab.chat)
                    .tabItem { EmptyView() }

                ProfileCenterView()
                    .tag(RootTab.profile)
                    .tabItem { EmptyView() }
            }
            .toolbar(.hidden, for: .tabBar)
        }
        // ⬇️ 여기서 CallingView를 띄움 (엔진/워처 주입)
        .fullScreenCover(isPresented: $isCallPresented) {
            CallingView(call: callEngine, watcher: matchWatcher) {
                appState.stopAutoMatching()
                resetPresentationForNextRoom()
            }
        }
        // 새 roomId가 잡히면 1회만 표시
        .onChange(of: callEngine.currentRoomId) { roomId in
            if let roomId { presentCall(roomId: roomId) }
        }
        // 상대/세션 종료 시 닫기
        .onChange(of: callEngine.remoteEnded) { ended in
            if ended { resetPresentationForNextRoom() }
        }
        // 매칭 감시 시작 + 초기 selfHeal
        .onAppear {
            matchWatcher.start()
            FunctionsAPI.selfHealIfDanglingRoomThen { _ in }
        }
        // ✅ [추가 #1] 통화 종료 시 Call 탭으로 강제 이동 + 자동매칭 중단
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WonderMinute.NavigateToCall"))) { _ in
            appState.stopAutoMatching()
            selection = .call
            if isCallPresented { resetPresentationForNextRoom() }
        }
        // ✅ [추가 #2] 포그라운드 복귀하면 dangling 즉시 자가치유
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            FunctionsAPI.selfHealIfDanglingRoomThen { _ in }
        }
        // ✅ 웜보이스 하단 탭바 (글래스 바 + 그라데이션 링 + 소프트 글로우)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                TabChip(system: "phone.fill", title: "전화",
                        isOn: selection == .call) { selection = .call }
                TabChip(system: "clock.fill", title: "기록",
                        isOn: selection == .history) { selection = .history }
                TabChip(system: "bubble.left.and.bubble.right.fill", title: "채팅",
                        isOn: selection == .chat) { selection = .chat }
                TabChip(system: "person.crop.circle", title: "나",
                        isOn: selection == .profile) { selection = .profile }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                // 부드러운 글래스 바 + 그라데이션 링
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(colors: [
                                    Color(red: 1.00, green: 0.47, blue: 0.58).opacity(0.55), // rose
                                    Color(red: 1.00, green: 0.70, blue: 0.44).opacity(0.55)  // peach
                                ], startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1
                            )
                            .blendMode(.overlay)
                    )
                    .shadow(color: Color(red: 1.00, green: 0.47, blue: 0.58).opacity(0.12), radius: 18, y: 6)

                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Presentation Guard
    private func presentCall(roomId: String) {
        guard !isCallPresented else { return }
        guard presentedForRoom != roomId else { return }

        // 🔎 서버 기준으로 방/세션이 살아있는지 검증
        verifyRoomIsActiveOnServer(roomId: roomId) { isActive in
            if isActive {
                presentedForRoom = roomId
                isCallPresented = true
            } else {
                // ❌ 유령/종료 세션이면 즉시 정리
                resetPresentationForNextRoom()
                appState.stopAutoMatching()           // 자동매칭도 끔 (원하면 alsoCancelQueue:true)
                callEngine.currentRoomId = nil        // 혹시라도 남아있으면 클리어
            }
        }
    }

    private func verifyRoomIsActiveOnServer(roomId: String, _ done: @escaping (Bool)->Void) {
        let db = Firestore.firestore()
        let rooms = db.collection("matchedRooms").document(roomId)
        let sessions = db.collection("callSessions").document(roomId)

        // 둘 다 서버 스냅샷만
        rooms.getDocument(source: .server) { rSnap, _ in
            sessions.getDocument(source: .server) { sSnap, _ in
                let roomExists = (rSnap?.exists == true)
                let status = (sSnap?.get("status") as? String) ?? "pending"
                let active = roomExists && (status == "active")
                done(active)
            }
        }
    }


    private func resetPresentationForNextRoom() {
        presentedForRoom = nil
        isCallPresented = false
        // 다음 매칭 때만 다시 뜨도록 신호 초기화
        callEngine.currentRoomId = nil
        callEngine.remoteEnded   = false
    }

    private struct TabChip: View {
        let system: String
        let title: String
        let isOn: Bool
        let action: () -> Void

        @State private var glowPhase: CGFloat = 0

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: system)
                        .font(.system(size: isOn ? 16 : 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .padding(.leading, 1)

                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minWidth: 78, maxWidth: 98)
                .background(
                    ZStack {
                        // 비활성: 은은한 글래스
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(isOn ? .clear : Color.white.opacity(0.10))

                        // 활성: 그라데이션 오라 + 소프트 글로우
                        if isOn {
                            // 내부 베이스
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(
                                    LinearGradient(colors: [
                                        Color(red: 0.98, green: 0.49, blue: 0.62).opacity(0.95), // rose
                                        Color(red: 1.00, green: 0.62, blue: 0.42).opacity(0.95)  // peach
                                    ], startPoint: .leading, endPoint: .trailing)
                                )

                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(colors: [
                                        Color(red: 0.99, green: 0.50, blue: 0.62).opacity(0.55),
                                        Color(red: 1.00, green: 0.69, blue: 0.43).opacity(0.55)
                                    ], startPoint: .leading, endPoint: .trailing),
                                    lineWidth: 2
                                )
                                .blur(radius: 6)
                                .opacity(0.7)


                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(colors: [
                                        Color(red: 1.00, green: 0.47, blue: 0.58).opacity(0.35),
                                        Color(red: 1.00, green: 0.70, blue: 0.44).opacity(0.35)
                                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 3
                                )

                                .scaleEffect(1 + 0.015 * CGFloat(sin(Double(glowPhase))))
                                .opacity(0.7 + 0.3 * Double(sin(Double(glowPhase))))
                                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: glowPhase)

                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    // 라이트 스트로크 (활성 시 더 선명)
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(isOn ? Color.white.opacity(0.28) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .foregroundColor(isOn ? .white : .white.opacity(0.92))
                .shadow(color: isOn ? Color(red: 1.00, green: 0.47, blue: 0.58).opacity(0.25) : .clear, radius: 10, y: 4)
                .shadow(color: isOn ? Color(red: 1.00, green: 0.70, blue: 0.44).opacity(0.18) : .clear, radius: 12, y: 6)
                .scaleEffect(isOn ? 1.04 : 1.0)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onAppear {
                    // 활성 탭일 때만 부드러운 숨쉬기 애니메이션 구동
                    if isOn { glowPhase = .pi / 2 }
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isOn)
        }
    }
}
