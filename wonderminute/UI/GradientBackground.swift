import SwiftUI

struct GradientBackground: View {
    var body: some View {
        // 따뜻한 아이보리 수직 그라데이션(전역 테마)
        AppTheme.gradient
            .ignoresSafeArea()
    }
}
