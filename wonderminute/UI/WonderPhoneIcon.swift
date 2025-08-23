import SwiftUI

struct WonderPhoneIcon: View {
    var size: CGFloat = 96
    var rotation: Double = -18 // 살짝 기울임으로 차별화

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 전화기 심볼
            Image(systemName: "phone.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .rotationEffect(.degrees(rotation))
                .padding(size * 0.12)
                .frame(width: size, height: size)
                .foregroundStyle(AppTheme.gradient) // 그라데이션 적용
                .background(
                    Circle()
                        .fill(.white.opacity(0.0)) // 투명 배경 유지
                )

            // "원더미닛" 포인트: 작은 분 점 (minute dot)
            Circle()
                .fill(AppTheme.gradient)
                .frame(width: size * 0.18, height: size * 0.18)
                .offset(x: size * 0.02, y: size * 0.02)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
