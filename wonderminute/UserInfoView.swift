import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore

struct UserInfoView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = UserOnboardingVM()
    
    @State private var step: OnbStep = .nickname
    @Namespace private var progressNS
    
    // ✅ 전화 인증 상태
       @State private var phoneVerified = false
       @State private var phoneE164 = ""
       @State private var showPhoneSheet = false
       @State private var isLoadingPhoneState = true

    
    // UserDefaults 키
    private let kOnbStepKey = "onb.step"
    private let kOnbNicknameKey = "onb.nickname"
    private let kOnbGenderKey = "onb.gender"
    private let kOnbInterestsKey = "onb.interests"
    private let kOnbMbtiKey = "onb.mbti"
    private let kOnbTeToEgKey = "onb.teToEg"
    
    var body: some View {
        ZStack {
            // 🔄 앱 공통 배경으로 교체
            GradientBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                header

                VStack(spacing: 18) {
                    // ✅ 전화 인증 유도 배너 (미인증 시)
                    if !isLoadingPhoneState && !phoneVerified {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.black)
                            Text("안전한 이용을 위해 전화번호 인증이 필요해요.")
                                .foregroundColor(.black)
                                .lineLimit(2)
                            Spacer()
                            Button("인증하기") { showPhoneSheet = true }
                                .font(.callout.bold())
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                                .foregroundColor(.black)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                    }

                    // 단계 타이틀/설명
                    Text(step.title)
                        .font(.title2.bold())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(step.subtitle)
                        .font(.callout)
                        .foregroundColor(.black.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // 🔄 단계별 콘텐츠 카드: 글래스 스타일
                    contentFor(step)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 12)

                    if let e = vm.errorMsg {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.footnote.bold())
                            Text(e)
                                .font(.footnote.bold())
                        }
                        .foregroundColor(.red.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Spacer(minLength: 8)
                footer
            }
            .padding(.bottom, 12)

            // 🔄 로딩 오버레이 (저장 중)
            if vm.isLoading {
                LoadingOverlayOnb(
                    title: vm.showSavingETA
                    ? "저장 중… 약 \(Int(ceil(vm.etaRemaining)))초 남음"
                    : "저장 중…",
                    progress: vm.showSavingETA && vm.etaTotal > 0
                    ? max(0, (vm.etaTotal - vm.etaRemaining) / vm.etaTotal)
                    : nil
                )
                .transition(.opacity)
            }
        }

        // ✅ 전화 인증 시트
        .sheet(isPresented: $showPhoneSheet) {
            NavigationView {
                PhoneVerifyView { phone in
                    self.phoneE164 = phone
                    self.phoneVerified = true
                    Task { try? await savePhoneFlag(phone: phone) }
                    self.showPhoneSheet = false
                }
                .navigationTitle("전화번호 인증")
                .navigationBarTitleDisplayMode(.inline)
                .padding()
            }
        }

        // UserDefaults 저장
        .onChange(of: step) { s in UserDefaults.standard.set(s.rawValue, forKey: kOnbStepKey) }
        .onChange(of: vm.nickname) { v in UserDefaults.standard.set(v, forKey: kOnbNicknameKey) }
        .onChange(of: vm.gender) { v in UserDefaults.standard.set(v, forKey: kOnbGenderKey) }
        .onChange(of: vm.interests) { v in UserDefaults.standard.set(v, forKey: kOnbInterestsKey) }
        .onChange(of: vm.mbti) { v in UserDefaults.standard.set(v, forKey: kOnbMbtiKey) }
        .onChange(of: vm.teToEg) { v in UserDefaults.standard.set(v, forKey: kOnbTeToEgKey) }

        // PhotosPicker → UIImage
        .onChange(of: vm.selectedItem) { newItem in
            Task {
                guard let data = try? await newItem?.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else { return }
                vm.profileImage = uiImage
            }
        }

        // 초기화
        .onAppear {
            if let raw = UserDefaults.standard.value(forKey: kOnbStepKey) as? Int,
               let s = OnbStep(rawValue: raw) { step = s }
            vm.nickname  = UserDefaults.standard.string(forKey: kOnbNicknameKey)  ?? vm.nickname
            vm.gender    = UserDefaults.standard.string(forKey: kOnbGenderKey)    ?? vm.gender
            vm.interests = UserDefaults.standard.array(forKey: kOnbInterestsKey) as? [String] ?? vm.interests
            vm.mbti      = UserDefaults.standard.string(forKey: kOnbMbtiKey)      ?? vm.mbti
            vm.teToEg    = UserDefaults.standard.string(forKey: kOnbTeToEgKey)    ?? vm.teToEg

            Task { await fetchPhoneStateAndMaybeOpenSheet() }
        }
    }

    
    // 상단 진행 헤더
    private var header: some View {
        let dotOn    = Color.black
        let dotOff   = Color.black.opacity(0.35)
        return VStack(spacing: 14) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 따뜻한 다크(웜보이스 톤) – 너무 새까맣지 않게
                    let barBase  = Color.black.opacity(0.15)
                    let barFill  = Color.black.opacity(0.85)
                    

                    // header 내부
                    Capsule().fill(barBase)
                    Capsule()
                        .fill(barFill)
                        .frame(width: geo.size.width * CGFloat(step.rawValue + 1) / CGFloat(OnbStep.allCases.count))
                        .matchedGeometryEffect(id: "progress", in: progressNS)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            HStack(spacing: 8) {
                ForEach(OnbStep.allCases, id: \.self) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? dotOn : dotOff)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
    
    // 하단 내비게이션
    private var footer: some View {
        let peach  = Color(red: 1.00, green: 0.86, blue: 0.70)
        let coral  = Color(red: 0.98, green: 0.53, blue: 0.47)
        let ivory  = Color(red: 1.00, green: 0.98, blue: 0.96)
       return HStack(spacing: 12) {
            Button {
                vm.errorMsg = nil
                if let prev = OnbStep(rawValue: step.rawValue - 1) { step = prev }
            } label: {
                

                // 이전 (글래스톤 + 블랙 텍스트)
                Label("이전", systemImage: "chevron.left")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.black)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
            .disabled(step == .nickname)
            .opacity(step == .nickname ? 0.5 : 1)
            
            Button {
                vm.errorMsg = nil
                if step == .teToEg {
                    guard phoneVerified else {
                                            vm.errorMsg = "전화번호 인증을 완료해주세요."
                                            showPhoneSheet = true
                                            return
                                        }
                    let all = vm.validateAll()
                    if !all.ok {
                        vm.errorMsg = "\(all.firstFail!.title)를(을) 완료해주세요."
                        step = all.firstFail!
                        return
                    }
                    Task {
                        do {
                            try await vm.saveProfile()
                            appState.setView(.mainTabView, reason: "userInfo saved profile")
                        } catch {
                            vm.errorMsg = (error as NSError).localizedDescription
                        }
                    }
                } else {
                    guard vm.validate(step: step) else {
                        vm.errorMsg = "\(step.title)를(을) 완료해주세요."
                        return
                    }
                    if let next = OnbStep(rawValue: step.rawValue + 1) { step = next }
                }
            } label: {
                // 다음 / 시작하기 (웜 그라데이션)
                let canProceed = (vm.validate(step: step) || step == .teToEg)
                                 && (step != .teToEg || phoneVerified)

                Text(step == .teToEg ? "시작하기" : "다음")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.black)
                    .background(
                        Group {
                            if canProceed {
                                LinearGradient(colors: [peach, coral],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)
                            } else {
                                // 비활성: 아이보리 톤
                                LinearGradient(colors: [ivory.opacity(0.9), ivory.opacity(0.8)],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(canProceed ? 0.12 : 0.08), lineWidth: 1)
                    )
                               
            }
            .disabled(!((vm.validate(step: step) || step == .teToEg)
                        && (step != .teToEg || phoneVerified)))

        }
        .padding(.horizontal, 20)
    }
    
    // 단계별 콘텐츠
    @ViewBuilder
    private func contentFor(_ step: OnbStep) -> some View {
        switch step {
        case .nickname:
            NicknameStep(nickname: $vm.nickname)
        case .gender:
            SegmentedStep(title: "성별", selection: $vm.gender, options: vm.genderOptions)
        case .photo:
            PhotoStep(profileImage: $vm.profileImage, selectedItem: $vm.selectedItem)
        case .interests:
            InterestStep(interests: $vm.interests, options: vm.interestOptions)
        case .mbti:
            PillsGridStep(selection: $vm.mbti, options: vm.mbtiOptions, adaptiveMin: 64)
        case .teToEg:
            SegmentedStep(title: "나는…", selection: $vm.teToEg, options: vm.teToEgOptions)
        }
    }
    
    // MARK: - 전화 인증 상태/저장 헬퍼
      private func fetchPhoneStateAndMaybeOpenSheet() async {
          guard let user = Auth.auth().currentUser else { return }
          do {
              let doc = try await Firestore.firestore().collection("users").document(user.uid).getDocument()
              let verified = (doc.data()?["phoneVerified"] as? Bool) == true
              let number = (doc.data()?["phoneNumberE164"] as? String) ?? (user.phoneNumber ?? "")
              await MainActor.run {
                  self.phoneVerified = verified || !number.isEmpty
                  self.phoneE164 = number
                  self.isLoadingPhoneState = false
                  if !self.phoneVerified { self.showPhoneSheet = true }   // 부드럽게 자동 오픈
              }
          } catch {
              await MainActor.run {
                  self.isLoadingPhoneState = false
                  // 네트워크 에러 시엔 배너만 남기고 수동으로 열 수 있게 둠
              }
          }
      }

      private func savePhoneFlag(phone: String) async throws {
          guard let uid = Auth.auth().currentUser?.uid else { return }
          try await Firestore.firestore().collection("users").document(uid).setData([
              "phoneVerified": true,
              "phoneNumberE164": phone
          ], merge: true)
      }
  }


// MARK: - 서브뷰들 (이 파일 내 전역)
struct NicknameStep: View {
    @Binding var nickname: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("닉네임")
                .font(.caption.weight(.semibold))
                .foregroundColor(.black.opacity(0.9))

            // 글래스 인풋
            ZStack(alignment: .leading) {
                if nickname.isEmpty {
                    Text("닉네임 입력")
                        .foregroundColor(.black.opacity(0.45))
                        .padding(.horizontal, 12)
                }
                TextField("", text: $nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
            }
            .frame(height: 44)
            .background(Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
    }
}

// 성별/성향 등 세그먼트
struct SegmentedStep: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.black)

            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .tint(.black)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
        }
    }
}

// 프로필 사진
struct PhotoStep: View {
    @Binding var profileImage: UIImage?
    @Binding var selectedItem: PhotosPickerItem?
    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.12))
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.black.opacity(0.9))
                    }
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 8)

            // 🔄 가독성 좋은 글래스 캡슐 버튼
            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 14, weight: .bold))
                    Text("앨범에서 선택")
                        .font(.callout.weight(.semibold))
                }
                .foregroundColor(.black)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
            }

            Text("괜찮아요, 건너뛰어도 됩니다.")
                .font(.footnote)
                .foregroundColor(.black.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

// 관심사
struct InterestStep: View {
    @Binding var interests: [String]
    let options: [String]
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("관심사 선택 (복수 선택 가능)")
                .font(.headline)
                .foregroundColor(.black)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(options, id: \.self) { item in
                    SelectablePill(title: item, isSelected: interests.contains(item)) {
                        if interests.contains(item) {
                            interests.removeAll { $0 == item }
                        } else {
                            guard interests.count < 6 else {
                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                return
                            }
                            interests.append(item)
                        }
                    }
                }
            }
        }
    }
}

// MBTI 등 픽(그리드)
struct PillsGridStep: View {
    @Binding var selection: String
    let options: [String]
    var adaptiveMin: CGFloat = 60
    var body: some View {
        let columns = [GridItem(.adaptive(minimum: adaptiveMin), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { opt in
                SelectablePill(title: opt, isSelected: selection == opt) {
                    selection = opt
                }
            }
        }
    }
}

// 글래스 필 선택형 Pill
// 글래스 필 선택형 Pill
struct SelectablePill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(minWidth: 60)
            .background(
                ZStack {
                    // 기본 배경
                    Color.white.opacity(0.14)
                    // 선택 시 덮어씌울 그라데이션
                    LinearGradient(
                        colors: [Color.green.opacity(0.9), Color.green.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(isSelected ? 1 : 0)
                }
            )
            .foregroundColor(.black)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(isSelected ? 0.35 : 0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.28 : 0.18), radius: isSelected ? 12 : 8, y: 6)
            .onTapGesture(perform: action)
    }
}

// MARK: - 온보딩 로딩 오버레이
fileprivate struct LoadingOverlayOnb: View {
    let title: String
    let progress: Double?   // 0.0 ~ 1.0 (없으면 무한 스피너)

    @State private var spin = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 74, height: 74)

                    if let _ = progress {
                        // 진행바 있을 때에도 링 스피너는 유지(가벼운 생동감)
                        Circle()
                            .trim(from: 0.08, to: 0.92)
                            .stroke(style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                            .foregroundColor(.white.opacity(0.95))
                            .frame(width: 74, height: 74)
                            .rotationEffect(.degrees(spin ? 360 : 0))
                            .animation(.linear(duration: 1.05).repeatForever(autoreverses: false), value: spin)
                    } else {
                        Circle()
                            .trim(from: 0.08, to: 0.92)
                            .stroke(style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                            .foregroundColor(.white.opacity(0.95))
                            .frame(width: 74, height: 74)
                            .rotationEffect(.degrees(spin ? 360 : 0))
                            .animation(.linear(duration: 1.05).repeatForever(autoreverses: false), value: spin)
                    }

                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .shadow(color: .white.opacity(0.25), radius: 6, y: 2)
                }
                .padding(.bottom, 2)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    if let progress {
                        ProgressView(value: progress)
                            .frame(width: 220)
                            .tint(.white)
                    } else {
                        // 보조 설명이 필요하면 여기에 footnote 추가 가능
                        EmptyView()
                    }
                }
                .padding(.horizontal, 6)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, y: 12)
            .padding(.horizontal, 40)
            .onAppear { spin = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title)"))
    }
}


