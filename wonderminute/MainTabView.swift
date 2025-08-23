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
        // ✅ 하단 탭칩 인셋 — 이건 단 한 번만!
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
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
        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: system).font(.system(size: 14, weight: .semibold))
                    Text(title).font(.system(size: 12, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.9)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 78, maxWidth: 96)
                .background {
                    if isOn {
                        LinearGradient(colors: [AppTheme.purple, AppTheme.blue],
                                       startPoint: .leading, endPoint: .trailing)
                    } else {
                        Color.white.opacity(0.10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isOn ? Color.white.opacity(0.22) : Color.white.opacity(0.10), lineWidth: 1)
                )
                .foregroundColor(isOn ? .white : .white.opacity(0.90))
                .scaleEffect(isOn ? 1.02 : 1.0)
                .animation(.spring(response: 0.26, dampingFraction: 0.9), value: isOn)
            }
        }
    }
}
