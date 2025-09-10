import SwiftUI

enum AppTheme {
    // --------------------------------------------
    // 레거시(보라/블루) 팔레트 — 필요 시 일부 화면에서 사용
    // --------------------------------------------
    static let purpleLegacy = Color(hex: 0x7C4DFF)
    static let indigoLegacy = Color(hex: 0x5B6CFF)
    static let blueLegacy   = Color(hex: 0x2196F3)
    
    static let legacyGradient = LinearGradient(
        colors: [purpleLegacy, blueLegacy],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // --------------------------------------------
    // 신규 ‘따뜻한’ 팔레트 (아이콘 컨셉)
    // --------------------------------------------
    // 배경(아이보리 계열)
    static let ivoryTop    = Color(red: 1.00, green: 0.98, blue: 0.96)
    static let ivoryBottom = Color(red: 1.00, green: 0.96, blue: 0.93)
    
    // 포인트(핑크/피치 계열)
    static let pink  = Color(red: 1.00, green: 0.80, blue: 0.84)
    static let peach = Color(red: 1.00, green: 0.86, blue: 0.70)
    static let apricot = Color(red: 1.00, green: 0.74, blue: 0.55)
    static let coral   = Color(red: 0.98, green: 0.53, blue: 0.47)
    
    // 텍스트(따뜻한 다크 브라운)
    static let textPrimary   = Color(red: 0.24, green: 0.20, blue: 0.19)
    static let textSecondary = Color(red: 0.48, green: 0.43, blue: 0.42)
    
    // 메인 그라데이션: 앱 전역 배경 (아이보리 수직)
    static let gradient = LinearGradient(
        colors: [ivoryTop, ivoryBottom],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // 액션/버튼 그라데이션(핑크 → 피치)
    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.65, blue: 0.66),
            Color(red: 1.00, green: 0.78, blue: 0.60)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    // 글래스/오버레이 톤(아이보리 배경에 어울리게 살짝 낮춤)
    static let glass = Color.white.opacity(0.14)
    
    // ==============================
    // Backward-compat for legacy refs
    // 기존 코드에서 쓰던 AppTheme.purple / .indigo / .blue 등
    // ==============================
    static let purple = purpleLegacy
    static let indigo = indigoLegacy
    static let blue   = blueLegacy

    // 일부 화면이 예전 보라-블루 그라데이션을 직접 기대한다면 사용
    static let primaryGradientLegacy = legacyGradient

    // 텍스트도 예전(화이트) 기대하는 화면이 있을 수 있어 보조 토큰 제공
    static let textPrimaryLegacy   = Color.white
    static let textSecondaryLegacy = Color.white.opacity(0.82)
   

}
