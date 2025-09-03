import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage          // ⬅️ 사진 업로드
import PhotosUI                 // ⬅️ 사진 선택(PhotosPicker)


// MARK: - WonderMinute Theme
extension Color {
    static let wmPrimary = Color(red: 0.48, green: 0.38, blue: 1.0)   // 브랜드 보라색
    static let wmBgTop   = Color(red: 0.41, green: 0.30, blue: 1.0)
    static let wmBgBot   = Color(red: 0.67, green: 0.58, blue: 1.0)
}

struct WMFormModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(LinearGradient(colors: [.wmBgTop, .wmBgBot],
                                       startPoint: .top, endPoint: .bottom))
            .tint(Color.wmPrimary)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .preferredColorScheme(.light)   // 라이트 고정
    }
}

extension View {
    func wonderMinuteForm() -> some View { modifier(WMFormModifier()) }
}


// MARK: - Enumerations

enum BlockReason: String, CaseIterable, Identifiable {
    case harassment = "폭언/혐오"
    case sexual     = "성적 발언/요구"
    case scam       = "불법/사기"
    case spam       = "스팸/광고"
    case minor      = "미성년 의심"
    case other      = "기타"

    var id: String { rawValue }
}

enum ReportType: String, CaseIterable, Identifiable {
    case harassment = "폭언/혐오"
    case sexual     = "성적 발언/요구"
    case scam       = "불법/사기"
    case spam       = "스팸/광고"
    case minor      = "미성년 의심"
    case other      = "기타"

    var id: String { rawValue }
}

// MARK: - SafetyCenter (Singleton)

final class SafetyCenter: ObservableObject {
    static let shared = SafetyCenter()
    private init() {}
    
    private let db = Firestore.firestore()
    
    // 로컬 캐시 (내가 차단한 UID 목록)
    @Published private(set) var blockedUids: Set<String> = []
    
    /// 앱 시작/로그인 후 한 번 로드(또는 포그라운드 복귀 때 갱신)
    func loadBlockedUids(completion: (() -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else { completion?(); return }
        db.collection("users").document(uid).collection("privacy").document("blocked")
            .getDocument { [weak self] snap, _ in
                let arr = (snap?.get("uids") as? [String]) ?? []
                self?.blockedUids = Set(arr)
                completion?()
            }
    }
    
    /// 차단 생성: blocks 컬렉션 + 내 프라이버시 캐시 업데이트
    func createBlock(blockedUid: String,
                     reason: BlockReason,
                     note: String?,
                     source: String = "call",
                     completion: @escaping (Bool) -> Void)
    {
        guard let me = Auth.auth().currentUser?.uid else { completion(false); return }
        if blockedUid == me { completion(false); return }
        
        let docId = "\(me)_\(blockedUid)"
        let now = FieldValue.serverTimestamp()
        let blocksRef = db.collection("blocks").document(docId)
        let batch = db.batch()
        
        // 1) blocks 문서
        batch.setData([
            "blockerUid": me,
            "blockedUid": blockedUid,
            "reasonCode": reason.rawValue,
            "note": note ?? "",
            "source": source,
            "status": "active",
            "effectScopes": ["match","message","call"],
            "createdAt": now
        ], forDocument: blocksRef, merge: true)
        
        // 2) users/{me}/privacy/blocked.uids 배열 캐시
        let myBlockedRef = db.collection("users").document(me)
            .collection("privacy").document("blocked")
        batch.setData([
            "uids": FieldValue.arrayUnion([blockedUid]),
            "updatedAt": now
        ], forDocument: myBlockedRef, merge: true)
        
        // 3) (옵션) 재매칭 제외 퍼블리시: matchingQueue/{me}.exclusions
        let queueRef = db.collection("matchingQueue").document(me)
        batch.setData([
            "exclusions": FieldValue.arrayUnion([blockedUid]),
            "updatedAt": now
        ], forDocument: queueRef, merge: true)
        
        batch.commit { [weak self] err in
            if err == nil {
                self?.blockedUids.insert(blockedUid)
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    /// 신고 생성: reports 컬렉션 onCreate → Functions 트리아지
    func submitReport(reportedUid: String,
                      roomId: String?,
                      callTimestampSec: Int?,
                      type: ReportType,
                      subtype: String?,
                      description: String,
                      attachments: [String] = [],
                      completion: @escaping (Bool) -> Void)
    {
        guard let me = Auth.auth().currentUser?.uid, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { completion(false); return }
        
        var ctx: [String: Any] = [:]
        if let roomId { ctx["roomId"] = roomId }
        if let callTimestampSec { ctx["timestampInCall"] = callTimestampSec }
        
        
        let data: [String: Any] = [
            "reporterUid": me,
            "reportedUid": reportedUid,
            "context": ctx,
            "type": type.rawValue,
            "subtype": subtype ?? "",
            "description": description,
            "attachments": attachments,
            "createdAt": FieldValue.serverTimestamp(),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "deviceInfo": UIDevice.current.model,
            "triage": ["status":"queued", "score": 0]
        ]
        
        db.collection("reports").addDocument(data: data) { err in
            completion(err == nil)
        }
    }
    
    /// 매칭 시작 전, 서버가 필터에 사용할 수 있도록 내가 차단한 목록을 퍼블리시
    func publishExclusionsForMatching(completion: ((Bool) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else { completion?(false); return }
        let arr = Array(blockedUids)
        let now = FieldValue.serverTimestamp()
        
        // users/{uid}/privacy/blocked 캐시를 먼저 새로고침(없을 수 있으니)
        db.collection("users").document(uid).collection("privacy").document("blocked")
            .setData(["uids": arr, "updatedAt": now], merge: true)
        
        db.collection("matchingQueue").document(uid)
            .setData(["exclusions": arr, "updatedAt": now], merge: true) { err in
                completion?(err == nil)
            }
    }
    
    /// 해당 상대와 매칭/통화를 허용해도 되는지 로컬 선판단(최종 게이트는 서버)
    func isAllowedToConnect(with peerUid: String) -> Bool {
        return !blockedUids.contains(peerUid)
    }
    // SafetyCenter 내부에 추가
    func unblock(_ uid: String, completion: @escaping (Bool) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else { completion(false); return }
        let now = FieldValue.serverTimestamp()
        let batch = db.batch()

        // 1) 내 캐시 배열에서 제거
        let myBlockedRef = db.collection("users").document(me)
            .collection("privacy").document("blocked")
        batch.setData(["uids": FieldValue.arrayRemove([uid]), "updatedAt": now],
                      forDocument: myBlockedRef, merge: true)

        // 2) 매칭 제외 배열에서도 제거
        let queueRef = db.collection("matchingQueue").document(me)
        batch.setData(["exclusions": FieldValue.arrayRemove([uid]), "updatedAt": now],
                      forDocument: queueRef, merge: true)

        // 3) blocks 문서 상태값 보정(있으면)  (me_uid 기준 단방향 차단 해제)
        let blockDocId = "\(me)_\(uid)"
        let blockRef = db.collection("blocks").document(blockDocId)
        batch.setData(
            ["status": "revoked", "revokedAt": now],
            forDocument: blockRef,
            merge: true
        )

        batch.commit { [weak self] err in
            if err == nil {
                self?.blockedUids.remove(uid)
                completion(true)
            } else {
                completion(false)
            }
        }
    }

}

// MARK: - SwiftUI Sheets

struct BlockSheetView: View {
    let peerUid: String
    let peerNickname: String
    let onCompleted: (_ didEndNow: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: BlockReason = .harassment
    @State private var note: String = ""
    @State private var endNow: Bool = true
    @State private var submitting = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Menu {
                        Picker("", selection: $reason) {
                            ForEach(BlockReason.allCases) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                    } label: {
                        HStack {
                            Text("사유").foregroundStyle(.primary)   // 글자색 보강
                            Spacer()
                            Text(reason.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("추가 메모(선택)", text: $note)
                } header: {
                    Text("차단 사유")
                }

                Section {
                    Toggle("현재 통화를 즉시 종료", isOn: $endNow)
                } footer: {
                    Text("차단 시 서로 **매칭/통화/메시지 요청이 노출되지 않아요**.")
                }
            }
            .navigationTitle("차단하기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(.primary)          // ← 버튼 색 명시
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "처리 중…" : "확인") { submit() }
                        .disabled(submitting)
                        .foregroundStyle(Color.wmPrimary)       // ← 브랜드 보라색
                }
            }
        }
        .wonderMinuteForm()                                  // ← 원더미닛 테마 적용

    }

    private func submit() {
        submitting = true
        SafetyCenter.shared.createBlock(blockedUid: peerUid, reason: reason, note: note) { ok in
            submitting = false
            if ok {
                dismiss()
                onCompleted(endNow) // 통화 즉시 종료 여부 콜백
            } else {
                errorMsg = "차단 처리에 실패했어요. 네트워크 상태를 확인해 주세요."
            }
        }
    }
}

struct ReportSheetView: View {
    let peerUid: String
    let peerNickname: String
    let roomId: String?
    let callElapsedSec: Int
    let onCompleted: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var type: ReportType = .harassment
    @State private var subtype: String = ""
    @State private var description: String = ""
    @State private var submitting = false
    @State private var errorMsg: String?
    
    @State private var pickedItems: [PhotosPickerItem] = []   // ⬅️ 선택된 포토 항목
    @State private var images: [UIImage] = []                 // ⬅️ 미리보기/업로드용
    @State private var uploadedURLs: [String] = []            // ⬅️ 업로드 결과(첨부)
    
    var body: some View {
        NavigationView {
            Form {
                // 1) 신고 유형
                Section {
                    Menu {
                        Picker("", selection: $type) {
                            ForEach(ReportType.allCases) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                    } label: {
                        HStack {
                            Text("유형").foregroundStyle(.primary)
                            Spacer()
                            Text(type.rawValue).foregroundStyle(.secondary)
                        }
                    }

                    TextField("세부 유형(선택)", text: $subtype)
                } header: {
                    Text("신고 유형")
                }

                // 2) 상세 설명
                Section {
                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                } header: {
                    Text("상세 설명(필수)")
                } footer: {
                    Text("허위 신고는 신고권 제한 등 제재를 받을 수 있어요. 보통 24시간 내 1차 검토됩니다.")
                }

                // 3) 자동 첨부(룸ID 비노출)
                Section {
                    HStack {
                        Text("통화 경과")
                        Spacer()
                        Text("\(callElapsedSec)초").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("자동 첨부")
                }

                // 4) 증거 사진
                Section {
                    PhotosPicker(selection: $pickedItems,
                                 maxSelectionCount: 5,
                                 matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text(images.isEmpty ? "사진 선택 (최대 5장)" : "사진 추가 선택")
                            Spacer()
                        }
                    }

                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(images.enumerated()), id: \.offset) { idx, img in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))

                                        Button {
                                            images.remove(at: idx)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .imageScale(.medium)
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .offset(x: 6, y: -6)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("증거 사진(선택)")
                }
                .onChange(of: pickedItems) { items in
                    Task {
                        var newImgs: [UIImage] = []
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                newImgs.append(img)
                            }
                        }
                        images.append(contentsOf: newImgs)
                        pickedItems.removeAll()
                    }
                }

                // 에러 표시
                if let e = errorMsg {
                    Section { Text(e).foregroundColor(.red) }
                }
            }

            .navigationTitle("신고하기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(.primary)              // 버튼 기본색
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "제출 중…" : "제출") { submit() }
                        .disabled(submitting || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .foregroundStyle(Color.wmPrimary)        // 버튼 보라색
                }
            }
        }
        .wonderMinuteForm()                                    // ← 테마 적용

    }
    
    private func submit() {
        submitting = true
        uploadAttachments(images) { urls in
            SafetyCenter.shared.submitReport(
                reportedUid: peerUid,
                roomId: roomId,
                callTimestampSec: callElapsedSec,
                type: type, subtype: subtype.isEmpty ? nil : subtype,
                description: description,
                attachments: urls                        // ⬅️ 업로드된 파일 URL
            ) { ok in
                submitting = false
                if ok {
                    dismiss()
                    onCompleted()
                } else {
                    errorMsg = "신고 제출에 실패했어요. 잠시 후 다시 시도해 주세요."
                }
            }
        }
    }
    
    private func uploadAttachments(_ images: [UIImage], completion: @escaping ([String]) -> Void) {
        guard !images.isEmpty else { completion([]); return }

        var urls: [String] = []
        let group = DispatchGroup()
        let storage = Storage.storage()

        let uid = Auth.auth().currentUser?.uid ?? "unknown"
        for (idx, img) in images.enumerated() {
            group.enter()
            let path = "report_attachments/\(uid)/\(Int(Date().timeIntervalSince1970))_\(idx).jpg"
            let ref  = storage.reference().child(path)
            let data = img.jpegData(compressionQuality: 0.8) ?? Data()

            ref.putData(data) { _, err in
                if err != nil {
                    group.leave()
                    return
                }
                ref.downloadURL { url, _ in
                    if let u = url?.absoluteString { urls.append(u) }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { completion(urls) }
    }

}


