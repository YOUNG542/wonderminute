import SwiftUI

enum AppTheme {
    // 핵심 팔레트
    static let purple = Color(hex: 0x7C4DFF)   // 보라
    static let indigo = Color(hex: 0x5B6CFF)   // 인디고
    static let blue   = Color(hex: 0x2196F3)   // 파랑

    // 메인 그라데이션 (아이콘 무드와 동일)
    static let gradient = LinearGradient(
        colors: [purple, blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // 글래스 버튼 배경
    static let glass = Color.white.opacity(0.18)

    // 텍스트
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.82)
}
