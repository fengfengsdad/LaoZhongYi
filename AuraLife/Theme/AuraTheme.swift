import SwiftUI
import UIKit

enum AuraTheme {
    // MARK: - Adaptive Surfaces
    static let canvasBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.086, green: 0.086, blue: 0.078, alpha: 1.0) // #161614 温润墨黑
            : UIColor(red: 0.980, green: 0.969, blue: 0.949, alpha: 1.0) // #FAF7F2 温润米白
    })

    static let cardSurface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.129, green: 0.125, blue: 0.114, alpha: 1.0) // #21201D 沉香深褐
            : UIColor(red: 1.000, green: 0.996, blue: 0.988, alpha: 1.0) // #FFFDFC 宣纸白
    })

    static let subtleSurface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.176, green: 0.173, blue: 0.157, alpha: 1.0) // #2D2C28
            : UIColor(red: 0.949, green: 0.929, blue: 0.894, alpha: 1.0) // #F2EDE4 素麻灰
    })

    static let hairline = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.09)
            : UIColor(red: 0.45, green: 0.41, blue: 0.35, alpha: 0.14)
    })

    // MARK: - Text Hierarchy
    static let primaryText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.945, green: 0.933, blue: 0.906, alpha: 1.0)
            : UIColor(red: 0.165, green: 0.157, blue: 0.141, alpha: 1.0) // #2A2824 柔墨
    })

    static let secondaryText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.678, green: 0.663, blue: 0.627, alpha: 1.0)
            : UIColor(red: 0.443, green: 0.420, blue: 0.380, alpha: 1.0) // #716B61 浅石
    })

    // MARK: - Eastern Minimalist Accents
    static let sageGreen = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.486, green: 0.667, blue: 0.545, alpha: 1.0) // #7CAA8B
            : UIColor(red: 0.380, green: 0.525, blue: 0.431, alpha: 1.0) // #61866E 鼠尾草绿
    })

    static let warmGinger = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.898, green: 0.659, blue: 0.310, alpha: 1.0) // #E5A84F
            : UIColor(red: 0.831, green: 0.569, blue: 0.227, alpha: 1.0) // #D4913A 暖姜黄
    })

    static let inkSlate = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.486, green: 0.608, blue: 0.706, alpha: 1.0) // #7C9BB4
            : UIColor(red: 0.345, green: 0.451, blue: 0.541, alpha: 1.0) // #58738A 黛青灰
    })

    static func accent(for category: ActionCategory) -> Color {
        switch category {
        case .diet:
            return sageGreen
        case .fitness:
            return warmGinger
        case .lifestyle:
            return inkSlate
        }
    }
}
