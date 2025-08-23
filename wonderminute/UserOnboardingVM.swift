import Foundation
import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

// 온보딩 단계
enum OnbStep: Int, CaseIterable {
    case nickname, gender, photo, interests, mbti, teToEg
    
    var title: String {
        switch self {
        case .nickname: return "닉네임"
        case .gender:   return "성별"
        case .photo:    return "프로필 사진(선택)"
        case .interests:return "관심사"
        case .mbti:     return "MBTI"
        case .teToEg:   return "테토/에겐"
        }
    }
    var subtitle: String {
        switch self {
        case .nickname:  return "기본 정보를 입력해주세요"
        case .gender:    return "성별을 선택해주세요"
        case .photo:     return "원하면 사진을 올려주세요"
        case .interests: return "관심사를 최소 1개 이상 선택"
        case .mbti:      return "당신의 MBTI를 고르세요"
        case .teToEg:    return "나는… 테토인/에겐인"
        }
    }
}

@MainActor
final class UserOnboardingVM: ObservableObject {
    // 입력값
    @Published var nickname: String = "" { didSet { scheduleNicknameCheck() } }
    @Published var gender: String = ""
    @Published var profileImage: UIImage? = nil
    @Published var interests: [String] = []
    @Published var mbti: String = ""
    @Published var teToEg: String = ""
    
    // 상태
    @Published var selectedItem: PhotosPickerItem? = nil
    @Published var isLoading: Bool = false
    @Published var errorMsg: String? = nil
    
    // 진행 ETA
    @Published var showSavingETA: Bool = false
    @Published var etaRemaining: TimeInterval = 0
    @Published var etaTotal: TimeInterval = 0
    private var etaTimer: Timer?
    
    // 닉네임 규칙 & 디바운스
    private let nicknameRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9가-힣._-]{2,12}$")
    private var nicknameCheckWorkItem: DispatchWorkItem?
    
    // 옵션들
    let genderOptions = ["남자", "여자"]
    let mbtiOptions = ["INTJ","INTP","ENTJ","ENTP","INFJ","INFP","ENFJ","ENFP","ISTJ","ISFJ","ESTJ","ESFJ","ISTP","ISFP","ESTP","ESFP"]
    let teToEgOptions = ["테토인", "에겐인"]
    let interestOptions = [
        "운동","음악","게임","여행","책","요리","영화","그림",
        "사진","패션","코딩","재테크","동물","산책","드라이브","자기계발",
        "명상","연극","전시회","봉사활동","자전거","카페 탐방","맛집","축구",
        "야구","K-POP","힙합","클래식","댄스","악기"
    ]
    
    // MARK: - 닉네임 검사
    private func isNicknameValidNow(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let range = NSRange(location: 0, length: (trimmed as NSString).length)
        return nicknameRegex.firstMatch(in: trimmed, options: [], range: range) != nil
    }
    
    private func scheduleNicknameCheck() {
        nicknameCheckWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var trimmed = self.nickname.trimmingCharacters(in: .whitespaces)
            if trimmed.count > 12 { trimmed = String(trimmed.prefix(12)) }
            let range = NSRange(location: 0, length: (trimmed as NSString).length)
            let ok = self.nicknameRegex.firstMatch(in: trimmed, options: [], range: range) != nil
            DispatchQueue.main.async {
                if self.nickname != trimmed { self.nickname = trimmed }
                self.errorMsg = ok ? nil : "닉네임은 2~12자, 영문/숫자/한글, . _ - 만 가능해요."
            }
        }
        nicknameCheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    
    // MARK: - 단계/전체 검증
    func validate(step: OnbStep) -> Bool {
        switch step {
        case .nickname: return isNicknameValidNow(nickname)
        case .gender:   return !gender.isEmpty
        case .photo:    return true
        case .interests:return !interests.isEmpty
        case .mbti:     return !mbti.isEmpty
        case .teToEg:   return !teToEg.isEmpty
        }
    }
    
    func validateAll() -> (ok: Bool, firstFail: OnbStep?) {
        for s in OnbStep.allCases {
            if !validate(step: s) { return (false, s) }
        }
        return (true, nil)
    }
    
    // MARK: - ETA 바
    private func beginETA(total seconds: TimeInterval) {
        etaTimer?.invalidate()
        etaTotal = max(0.5, seconds)
        etaRemaining = etaTotal
        showSavingETA = true
        etaTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] t in
            guard let self else { return }
            self.etaRemaining = max(0, self.etaRemaining - 0.2)
            if self.etaRemaining <= 0 { t.invalidate() }
        }
    }
    private func endETA() {
        etaTimer?.invalidate()
        etaTimer = nil
        showSavingETA = false
        etaRemaining = 0
        etaTotal = 0
    }
    
    // MARK: - 저장
    func saveProfile() async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "로그인 세션이 만료되었습니다. 다시 로그인해주세요."])
        }
        
        isLoading = true
        defer { isLoading = false; endETA() }
        
        // ETA 대략치
        var estimated: TimeInterval = 0.8
        if let img = profileImage, let data = img.jpegData(compressionQuality: 0.85) {
            let uploadSpeedMBps: Double = 1.5
            let sizeMB = Double(data.count) / (1024.0 * 1024.0)
            estimated += max(0.6, sizeMB / uploadSpeedMBps)
        }
        beginETA(total: estimated)
        
        let db  = Firestore.firestore()
        let ref = db.collection("users").document(uid)
        
        // 이전 URL 확보
        let oldSnap = try? await ref.getDocument(source: .server)
        let oldURL  = oldSnap?.data()?["profileImageUrl"] as? String
        
        // 공통 데이터
        var data: [String: Any] = [
            "uid": uid,
            "nickname": nickname,
            "gender": gender,
            "interests": interests,
            "mbti": mbti,
            "teToEg": teToEg,
            "profileCompleted": true,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if oldSnap?.exists != true {
            data["createdAt"] = FieldValue.serverTimestamp()
        }
        
        // 이미지 업로드 후 URL 반영
        if let img = profileImage {
            let newURL = try await uploadProfileImageAndGetURL(uid: uid, image: img, existingURL: oldURL)
            data["profileImageUrl"] = newURL
        }
        
        try await ref.setData(data, merge: true)
        
        // 저장 직후 강제 서버조회(캐시 무시)
        _ = try await ref.getDocument(source: .server)
    }
    
    private func uploadProfileImageAndGetURL(uid: String, image: UIImage, existingURL: String?) async throws -> String {
        // 기존 파일 제거(실패 무시)
        if let existingURL, let oldRef = try? Storage.storage().reference(forURL: existingURL) {
            try? await oldRef.delete()
        }
        // 캐시 무력화 경로
        let ts = Int(Date().timeIntervalSince1970)
        let path = "profileImages/\(uid)-\(ts).jpg"
        let ref  = Storage.storage().reference().child(path)
        
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "Upload", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "이미지 인코딩에 실패했습니다."])
        }
        _ = try await ref.putDataAsync(data, metadata: nil)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }
}
