import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage   // ⬅️ Storage 추가

private let profileMaxW: CGFloat = 340   // 프로필 화면용 최대 폭 (기존 360보다 살짝 좁게)


private struct LightCard: ViewModifier {
    var corner: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, y: 6)
    }
}
private extension View {
    func lightCard(corner: CGFloat = 16) -> some View { modifier(LightCard(corner: corner)) }
}


private enum EditTarget: Identifiable {
    case nickname(String)
    case gender(String)
    case mbti(String)
    case interests(Set<String>)
    case teToEg(String) // 테토/에겐

    var id: String {
        switch self {
        case .nickname:  return "nickname"
        case .gender:    return "gender"
        case .mbti:      return "mbti"
        case .interests: return "interests"
        case .teToEg:    return "teToEg"
        }
    }
}


// MARK: - ViewModel

final class ProfileVM: ObservableObject {
    // 🔧 프로필 필드들 (Firestore ↔️ UI 바인딩)
       @Published var gender: String = ""
       @Published var nickname: String = ""
       @Published var mbti: String = ""
       @Published var interests: [String] = []
       @Published var teToEg: String = ""        // 테토/에겐
       @Published var photoURL: String = ""      // Storage 다운 URL
    @Published var imageVersion: Int = 0
       // 상태
       @Published var isLoading: Bool = false
       @Published var isSaving: Bool = false
       @Published var errorMessage: String?

       private let db = Firestore.firestore()
       private var uid: String? { Auth.auth().currentUser?.uid }

    // 불러오기
    func load() {
        guard let uid else { return }
        isLoading = true
        db.collection("users").document(uid).getDocument { [weak self] snap, err in
            guard let self else { return }
            self.isLoading = false
            if let err { self.errorMessage = err.localizedDescription; return }
            guard let data = snap?.data() else { return }

            self.gender    = data["gender"] as? String ?? ""
            self.nickname  = data["nickname"] as? String ?? ""
            self.mbti      = data["mbti"] as? String ?? ""
            self.interests = data["interests"] as? [String] ?? []
            self.teToEg    = data["teToEg"] as? String ?? ""
            self.photoURL = (data["photoURL"] as? String)
                ?? (data["profileImageUrl"] as? String)   // ⬅️ 온보딩에서 쓴 키도 폴백
                ?? ""

        }
    }

    // 저장(일반 필드)
    func update(fields: [String: Any]) {
        guard let uid else { return }
        isSaving = true
        db.collection("users").document(uid).setData(fields, merge: true) { [weak self] err in
            guard let self else { return }
            self.isSaving = false
            if let err = err {
                self.errorMessage = err.localizedDescription
                return
            }
            // 로컬 상태 즉시 반영
            if let v = fields["nickname"]  as? String { self.nickname = v }
            if let v = fields["mbti"]      as? String { self.mbti = v }
            if let v = fields["interests"] as? [String] { self.interests = v }
            if let v = fields["teToEg"]    as? String { self.teToEg = v }
            if let v = fields["gender"]    as? String { self.gender = v }
            if let v = fields["photoURL"]  as? String { self.photoURL = v }
        }
    }

    // 사진 업로드 → downloadURL 저장
    func uploadProfileImage(_ image: UIImage) {
        guard let uid else { return }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            self.errorMessage = "이미지 인코딩에 실패했어요."
            return
        }
        isSaving = true

        let usersRef = db.collection("users").document(uid)

        // 1) 기존 URL 가져와서 삭제(선택)
        usersRef.getDocument(source: .server) { [weak self] snap, _ in
            guard let self else { return }
            let old = (snap?.data()?["profileImageUrl"] as? String) ?? (snap?.data()?["photoURL"] as? String)
            if let old, let oldRef = try? Storage.storage().reference(forURL: old) {
                oldRef.delete(completion: nil) // 실패해도 무시
            }

            // 2) 새 경로: uid-epoch.jpg
            let ts = Int(Date().timeIntervalSince1970)
            let path = "profileImages/\(uid)-\(ts).jpg"
            let ref  = Storage.storage().reference().child(path)
            let meta = StorageMetadata()
            meta.contentType = "image/jpeg"

            ref.putData(data, metadata: meta) { [weak self] _, err in
                guard let self else { return }
                if let err = err {
                    self.isSaving = false
                    self.errorMessage = "이미지 업로드 실패: \(err.localizedDescription)"
                    return
                }
                ref.downloadURL { url, err in
                    if let err = err {
                        self.isSaving = false
                        self.errorMessage = "URL 가져오기 실패: \(err.localizedDescription)"
                        return
                    }
                    guard let url else {
                        self.isSaving = false
                        self.errorMessage = "유효한 다운로드 URL이 없어요."
                        return
                    }

                    // 3) 문서 저장 — 키를 profileImageUrl로 통일(+1회 마이그레이션겸 photoURL도 써줌)
                    let urlStr = url.absoluteString
                    usersRef.setData([
                        "profileImageUrl": urlStr,
                        "photoURL": urlStr,            // ← 기존 코드 호환용(한 번 더 써줌)
                        "updatedAt": FieldValue.serverTimestamp()
                    ], merge: true) { [weak self] err in
                        guard let self else { return }
                        self.isSaving = false
                        if let err { self.errorMessage = err.localizedDescription; return }
                        // 로컬 상태 갱신
                        self.photoURL = urlStr
                        // (선택) 캐시버스터 증가
                        self.imageVersion &+= 1
                    }
                }
            }
        }
    }


    // 완료율(대략): 닉네임·MBTI·관심사(2개+)·한줄소개
    var completionRatio: Double {
        var score = 0
        if !nickname.trimmingCharacters(in: .whitespaces).isEmpty { score += 1 }
        if !mbti.isEmpty { score += 1 }
        if interests.count >= 2 { score += 1 }
        if !teToEg.trimmingCharacters(in: .whitespaces).isEmpty { score += 1 }
        return Double(score) / 4.0
    }
    var completionText: String {
        let pct = Int(round(completionRatio * 100))
        return "\(pct)% 완료"
    }
}

// MARK: - Center (Home)

struct ProfileCenterView: View {
    @StateObject private var vm = ProfileVM()
    
    // ✅ 단일 시트 상태
    @State private var activeEditor: EditTarget? = nil
    
    
    // 사진 선택
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    
    // 옵션 푸시
    @State private var goOptions = false
    
    var body: some View {
        NavigationView {
            ZStack {
                GradientBackground()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        infoSection
                        checklistCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                
                // 로딩/저장 오버레이
                if vm.isLoading || vm.isSaving {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView(vm.isSaving ? "저장 중..." : "불러오는 중...")
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("마이페이지").font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { goOptions = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .contentShape(Rectangle())
                }
            }
            .onAppear { vm.load() }
            .alert("에러", isPresented: Binding(get: { vm.errorMessage != nil },
                                              set: { _ in vm.errorMessage = nil })) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .background(
                NavigationLink("", destination: OptionView(), isActive: $goOptions)
                    .opacity(0)
            )
            .sheet(item: $activeEditor) { target in
                switch target {
                case .nickname(let current):
                    EditNicknameView(current: current) { newName in
                        vm.update(fields: ["nickname": newName])
                        activeEditor = nil
                    }
                    .presentationDetents([.large])
                case .gender(let current):
                    EditGenderView(current: current) { newGender in
                        vm.update(fields: ["gender": newGender])
                        activeEditor = nil
                    }
                    
                case .mbti(let current):
                    EditMBTIView(selected: current) { new in
                        vm.update(fields: ["mbti": new])
                        activeEditor = nil
                    }
                    
                case .interests(let current):
                    EditInterestsView(selected: current) { arr in
                        vm.update(fields: ["interests": arr])
                        activeEditor = nil
                    }
                    
                case .teToEg(let current):
                    EditTetoEgenView(current: current) { new in
                        vm.update(fields: ["teToEg": new])
                        activeEditor = nil
                    }
                    
                }
            }
            
            
        }
    }
    
    // MARK: Header
    
    private var headerCard: some View {
        VStack(spacing: 14) {
            ZStack {
                // 아바타
                Group {
                    if let img = pickedImage {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                    } else if let url = URL(string: vm.photoURL), !vm.photoURL.isEmpty {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { Color(white: 0.94) }
                    } else {
                        ZStack {
                            Color(white: 0.94)
                            Image(systemName: "person.crop.circle.fill")
                                .resizable().scaledToFit()
                                .foregroundColor(.black.opacity(0.25))
                                .padding(12)
                        }
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))

                // 완료율 링(그대로)
                Circle()
                    .trim(from: 0, to: vm.completionRatio)
                    .stroke(
                        AngularGradient(colors: [.purple, .blue, .purple], center: .center),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 108, height: 108)
                    .opacity(0.9)

                // 사진 편집 버튼
                if #available(iOS 16.0, *) {
                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white, .black.opacity(0.25))
                            .background(Circle().fill(Color.black.opacity(0.10)))
                    }
                    .onChange(of: pickedItem) { newItem in
                        guard let newItem else { return }
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                await MainActor.run { self.pickedImage = image }
                                vm.uploadProfileImage(image)
                            }
                        }
                    }
                    .offset(x: 40, y: 40)
                }
            }

            // 완료율 배지(어두운 텍스트)
            Text(vm.completionText)
                .font(.caption.bold())
                .foregroundColor(Color(hex: 0x1B2240))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: 0xEEF1F6)))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // headerCard 끝부분
        .lightCard(corner: 18)
        .frame(maxWidth: profileMaxW)
    }

    
    // MARK: Info list (각 항목 편집 → Firestore 반영)
    
    private var infoSection: some View {
        VStack(spacing: 10) {
            NavRow(title: "닉네임", value: vm.nickname.isEmpty ? "미설정" : vm.nickname) {
                activeEditor = .nickname(vm.nickname)
            }
            ReadonlyRow(title: "성별", value: vm.gender.isEmpty ? "-" : vm.gender)
            NavRow(title: "MBTI", value: vm.mbti.isEmpty ? "선택" : vm.mbti) {
                activeEditor = .mbti(vm.mbti)
            }
            NavRow(title: "관심사", value: vm.interests.isEmpty ? "선택" : vm.interests.joined(separator: ", ")) {
                activeEditor = .interests(Set(vm.interests))
            }
            NavRow(title: "테토/에겐", value: vm.teToEg.isEmpty ? "입력" : vm.teToEg) {
                activeEditor = .teToEg(vm.teToEg)
            }
        }
        .lightCard(corner: 16)   // ⬅️ 섹션 컨테이너를 흰 카드로
        .frame(maxWidth: profileMaxW)
    }

    
    
    // MARK: - Rows
    
    private struct NavRow: View {
        let title: String; let value: String; let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(hex: 0x1B2240))         // 다크 네이비

                    Spacer()

                    Text(value)
                        .font(.subheadline)
                        .foregroundColor(Color.black.opacity(0.7))

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(Color.black.opacity(0.25))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    
    private struct ReadonlyRow: View {
        let title: String; let value: String
        var body: some View {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color(hex: 0x1B2240))
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(Color.black.opacity(0.7))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
    }

    
    // MARK: - Editors
    
    private struct EditNicknameView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var text: String
        @State private var error: String? = nil
        @State private var checkWorkItem: DispatchWorkItem?

        let onSave: (String) -> Void

        // 온보딩과 동일 규칙: 2~12자, 영문/숫자/한글, . _ - 허용
        private static let nicknameRegex = try! NSRegularExpression(
            pattern: "^[A-Za-z0-9가-힣._-]{2,12}$"
        )

        init(current: String, onSave: @escaping (String) -> Void) {
            _text = State(initialValue: current)
            self.onSave = onSave
        }

        var body: some View {
            editorContainer(title: "닉네임") {
                TextField("닉네임을 입력하세요", text: $text)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .padding()
                  .background(Color(white: 0.95))                // 밝은 회색 배경 (흰 시트에서도 보임)
                  .overlay(                                       // 얇은 테두리로 윤곽 강조 (선택)
                      RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                  )
                  .foregroundColor(.primary)                      // 시스템 기본 텍스트 색(라이트/다크 자동 대응)
                  .onChange(of: text) { newValue in
                    validateDebounced(newValue)
                
                    }

                if let error {
                    Text(error)
                        .font(.footnote.bold())
                        .foregroundColor(.red)
                }
            } onSave: {
                // 저장 시 최종 한 번 더 확인
                validateNow(text)
                guard error == nil else {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return
                }
                onSave(text.trimmingCharacters(in: .whitespaces))
                dismiss()
            }
            .onAppear { validateDebounced(text) }
        }

        // MARK: - Validation

        private func validateDebounced(_ value: String) {
            checkWorkItem?.cancel()
            let work = DispatchWorkItem { [value] in
                validateNow(value)
            }
            checkWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        private func validateNow(_ value: String) {
            var t = value.trimmingCharacters(in: .whitespaces)
            // 길이 하드 컷
            if t.count > 12 { t = String(t.prefix(12)) }

            let range = NSRange(location: 0, length: (t as NSString).length)
            let ok = Self.nicknameRegex.firstMatch(in: t, options: [], range: range) != nil

            // 입력값이 바뀌었으면 반영
            if t != text { text = t }

            error = ok ? nil : "닉네임은 2~12자, 영문/숫자/한글, . _ - 만 가능해요."
        }
    }

    
    private struct EditGenderView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var selected: String
        let onSave: (String) -> Void
        init(current: String, onSave: @escaping (String) -> Void) {
            _selected = State(initialValue: current)
            self.onSave = onSave
        }
        // ⬇️ 기타 제거
        private let options = ["남자", "여자"]
        
        var body: some View {
            editorContainer(title: "성별") {
                Picker("성별", selection: $selected) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 6)
            } onSave: {
                onSave(selected)
                dismiss()
            }
        }
    }
    
    
    private struct EditMBTIView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var selected: String
        let onSave: (String) -> Void
        init(selected: String, onSave: @escaping (String) -> Void) {
            _selected = State(initialValue: selected)
            self.onSave = onSave
        }
        private let types = ["ISTJ","ISFJ","INFJ","INTJ","ISTP","ISFP","INFP","INTP",
                             "ESTP","ESFP","ENFP","ENTP","ESTJ","ESFJ","ENFJ","ENTJ"]
        var body: some View {
            editorContainer(title: "MBTI") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(types, id: \.self) { t in
                        Button {
                            selected = t
                        } label: {
                            Text(t)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(
                                    Group {
                                        if selected == t {
                                            LinearGradient(colors: [.purple, .blue],
                                                           startPoint: .leading, endPoint: .trailing)
                                        } else {
                                            Color(.secondarySystemBackground)
                                        }
                                    }
                                )
                                .foregroundColor((selected == t) ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            } onSave: {
                onSave(selected)
                dismiss()
            }
        }
    }
    
    private struct EditInterestsView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var selected: Set<String>
        let onSave: ([String]) -> Void
        init(selected: Set<String>, onSave: @escaping ([String]) -> Void) {
            _selected = State(initialValue: selected)
            self.onSave = onSave
        }
        private let presets = ["운동","게임","여행","요리","독서","영화","음악","K-POP","반려동물","패션","사진","공부","자기계발","카페","드라마","기술","코딩"]
        
        var body: some View {
            editorContainer(title: "관심사") {
                FlowLayout(alignment: .leading, spacing: 8) {
                    ForEach(presets, id: \.self) { tag in
                        TagChip(text: tag, isOn: selected.contains(tag)) {
                            if selected.contains(tag) { selected.remove(tag) } else { selected.insert(tag) }
                        }
                    }
                }
                .padding(.vertical, 8)
            } onSave: {
                onSave(Array(selected))
                dismiss()
            }
        }
    }
    
    
    private struct EditTetoEgenView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var selected: String
        let onSave: (String) -> Void
        
        init(current: String, onSave: @escaping (String) -> Void) {
            // current가 비어있으면 기본값을 테토인으로
            _selected = State(initialValue: current.isEmpty ? "테토인" : current)
            self.onSave = onSave
        }
        
        private let options = ["테토인", "에겐인"]
        
        var body: some View {
            editorContainer(title: "테토/에겐") {
                Picker("테토/에겐", selection: $selected) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 6)
            } onSave: {
                onSave(selected)
                dismiss()
            }
        }
    }
    
    // MARK: - Shared Editor Scaffold
    
    private struct DismissToolbarButton: View {
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            Button("닫기") { dismiss() }
                .tint(.primary)            // 라이트=검정, 다크=흰
                .foregroundColor(.primary) // 혹시 모를 케이스 대비
        }
    }
    
    // 교체: editorContainer (iOS16+ 기본 흰 배경으로)
    private static func editorContainer<V: View>(
      title: String,
      @ViewBuilder content: () -> V,
      onSave: @escaping () -> Void
    ) -> some View {
      Group {
        if #available(iOS 16.0, *) {
          NavigationStack {
            ScrollView {
              VStack(alignment: .leading, spacing: 16) { content() }
                .padding(16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .navigationBarLeading) { DismissToolbarButton() }
              ToolbarItem(placement: .navigationBarTrailing) { Button("저장", action: onSave).bold() }
            }
            // (선택) 하단 보조 바
            .safeAreaInset(edge: .bottom) {
              HStack {
                DismissToolbarButton()
                Spacer()
                Button("저장", action: onSave).bold().buttonStyle(.borderedProminent)
              }
              .padding(.horizontal, 16).padding(.vertical, 12)
              .background(.ultraThinMaterial)
            }
          }
          .tint(.purple)
          // 👉 투명 네비 배경은 사용하지 않음(흰 배경 유지)
          // .toolbarBackground(.clear, for: .navigationBar)  // 제거
          // .toolbarBackground(.visible, for: .navigationBar) // 제거

        } else {
          NavigationView {
            ScrollView {
              VStack(alignment: .leading, spacing: 16) { content() }
                .padding(16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .navigationBarLeading) { DismissToolbarButton() }
              ToolbarItem(placement: .navigationBarTrailing) { Button("저장", action: onSave).bold() }
            }
          }
          .tint(.purple)
        }
      }
    }

    
    
    
    // MARK: - Small UI helpers
    
    private struct TagChip: View {
        let text: String
        let isOn: Bool
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                Text(text)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        Group {
                            if isOn {
                                LinearGradient(colors: [.purple, .blue],
                                               startPoint: .leading, endPoint: .trailing)
                            } else {
                                Color(.secondarySystemBackground)
                            }
                        }
                    )
                    .foregroundColor(isOn ? .white : .primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
    
    // 간단한 흐름 레이아웃(태그 정렬용) — iOS 16+
    private struct FlowLayout<Content: View>: View {
        let alignment: HorizontalAlignment
        let spacing: CGFloat
        @ViewBuilder let content: () -> Content
        
        init(alignment: HorizontalAlignment = .leading,
             spacing: CGFloat = 8,
             @ViewBuilder content: @escaping () -> Content) {
            self.alignment = alignment
            self.spacing = spacing
            self.content = content
        }
        
        var body: some View {
            _FlowLayout(alignment: alignment, spacing: spacing) {
                content()
            }
        }
    }
    
    private struct _FlowLayout: Layout {
        let alignment: HorizontalAlignment
        let spacing: CGFloat
        
        func sizeThatFits(proposal: ProposedViewSize,
                          subviews: Subviews,
                          cache: inout ()) -> CGSize {
            let maxWidth = proposal.width ?? .infinity
            var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
            for s in subviews {
                let size = s.sizeThatFits(.unspecified)
                if x + size.width > maxWidth {
                    x = 0; y += rowH + spacing; rowH = 0
                }
                rowH = max(rowH, size.height)
                x += size.width + spacing
            }
            return CGSize(width: maxWidth, height: y + rowH)
        }
        
        func placeSubviews(in bounds: CGRect,
                           proposal: ProposedViewSize,
                           subviews: Subviews,
                           cache: inout ()) {
            var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
            for s in subviews {
                let size = s.sizeThatFits(.unspecified)
                if x + size.width > bounds.width {
                    x = 0; y += rowH + spacing; rowH = 0
                }
                s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                        proposal: ProposedViewSize(width: size.width, height: size.height))
                rowH = max(rowH, size.height)
                x += size.width + spacing
            }
        }
    }
    
    // MARK: Checklist(완성도 가이드)
    private var checklistCard: some View {
        let hasPhoto = (pickedImage != nil) || (!vm.photoURL.isEmpty)
        let hasNickname = !vm.nickname.trimmingCharacters(in: .whitespaces).isEmpty
        let hasMBTI = !vm.mbti.isEmpty
        let has2Interests = vm.interests.count >= 2
        let hasIntro = !vm.teToEg.trimmingCharacters(in: .whitespaces).isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("프로필 완성 가이드")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color(hex: 0x1B2240))
                Spacer()
                Text(vm.completionText) // 예: 75% 완료
                    .font(.footnote.weight(.bold))
                    .foregroundColor(Color(hex: 0x5A6AFF))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: 0xEEF1F6)))
            }

            CheckRow(title: "프로필 사진 추가",       done: hasPhoto)
            CheckRow(title: "닉네임 설정",           done: hasNickname)
            CheckRow(title: "MBTI 선택",            done: hasMBTI)
            CheckRow(title: "관심사 2개 이상 선택",   done: has2Interests)
            CheckRow(title: "한줄 소개(테토/에겐) 입력", done: hasIntro)
        }
        .lightCard(corner: 16)
        .frame(maxWidth: profileMaxW)
    }

    // 소형 체크 행
    private struct CheckRow: View {
        let title: String; let done: Bool
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(done ? Color(hex: 0x4E73FF) : Color.black.opacity(0.25))
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Color(hex: 0x1B2240).opacity(done ? 0.65 : 0.95))
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
        }
    }

}
