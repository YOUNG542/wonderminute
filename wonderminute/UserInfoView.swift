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
            LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                header
                
                VStack(spacing: 18) {
                    
                    // ✅ 인증 유도 배너 (인증 안 된 경우만)
                                       if !isLoadingPhoneState && !phoneVerified {
                                           HStack(spacing: 10) {
                                               Image(systemName: "phone.fill")
                                               Text("안전한 이용을 위해 전화번호 인증이 필요해요.")
                                                   .lineLimit(2)
                                               Spacer()
                                               Button("인증하기") { showPhoneSheet = true }
                                                   .buttonStyle(.borderedProminent)
                                           }
                                           .padding(12)
                                           .background(Color.yellow.opacity(0.2))
                                           .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                           .padding(.horizontal, 20)
                                       }
                    
                    Text(step.title)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(step.subtitle)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    contentFor(step)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(radius: 8, y: 4)
                    
                    if let e = vm.errorMsg {
                        Text(e)
                            .font(.footnote.bold())
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                Spacer(minLength: 8)
                footer
            }
            .padding(.bottom, 12)
            
            // 로딩 오버레이
            if vm.isLoading {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 12) {
                    Text(vm.showSavingETA
                         ? "저장 중… 약 \(Int(ceil(vm.etaRemaining)))초 남음"
                         : "저장 중…")
                        .font(.headline)
                    if vm.showSavingETA, vm.etaTotal > 0 {
                        ProgressView(value: max(0, (vm.etaTotal - vm.etaRemaining) / vm.etaTotal))
                            .frame(width: 200)
                    } else {
                        ProgressView().frame(width: 200)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
            }
        }
        
        // ✅ 전화 인증 시트 (라우팅은 그대로, 화면 위에서 처리)
               .sheet(isPresented: $showPhoneSheet) {
                   NavigationView {
                       PhoneVerifyView { phone in
                           self.phoneE164 = phone
                           self.phoneVerified = true
                           Task { try? await savePhoneFlag(phone: phone) } // 서버에도 반영
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
            vm.nickname = UserDefaults.standard.string(forKey: kOnbNicknameKey) ?? vm.nickname
            vm.gender = UserDefaults.standard.string(forKey: kOnbGenderKey) ?? vm.gender
            vm.interests = UserDefaults.standard.array(forKey: kOnbInterestsKey) as? [String] ?? vm.interests
            vm.mbti = UserDefaults.standard.string(forKey: kOnbMbtiKey) ?? vm.mbti
            vm.teToEg = UserDefaults.standard.string(forKey: kOnbTeToEgKey) ?? vm.teToEg
            
            Task { await fetchPhoneStateAndMaybeOpenSheet() }
        }
    }
    
    // 상단 진행 헤더
    private var header: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule()
                        .fill(.white)
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
                        .fill(s.rawValue <= step.rawValue ? .white : .white.opacity(0.35))
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
    
    // 하단 내비게이션
    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                vm.errorMsg = nil
                if let prev = OnbStep(rawValue: step.rawValue - 1) { step = prev }
            } label: {
                Label("이전", systemImage: "chevron.left")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white.opacity(0.15))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Text(step == .teToEg ? "시작하기" : "다음")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background( (vm.validate(step: step) || step == .teToEg)
                                                    && (step != .teToEg || phoneVerified)
                                                    ? Color.green : Color.gray)
                                       .foregroundColor(.white)
                                       .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                               
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
            TextField("닉네임 입력", text: $nickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color(white: 0.96))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct SegmentedStep: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct PhotoStep: View {
    @Binding var profileImage: UIImage?
    @Binding var selectedItem: PhotosPickerItem?
    var body: some View {
        VStack(spacing: 16) {
            if let image = profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.badge.plus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.secondary)
            }
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text("앨범에서 선택")
                    .bold()
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Color(white: 0.95))
                    .clipShape(Capsule())
            }
            Text("괜찮아요, 건너뛰어도 됩니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

struct InterestStep: View {
    @Binding var interests: [String]
    let options: [String]
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("관심사 선택 (복수 선택 가능)").font(.headline)
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
            .background(isSelected ? Color.green : Color(white: 0.96))
            .foregroundColor(.black)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.black.opacity(isSelected ? 0.15 : 0.07), lineWidth: 1)
            )
            .onTapGesture(perform: action)
    }
}
