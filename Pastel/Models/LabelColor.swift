import SwiftUI

/// Preset color palette for labels.
/// Raw values match the `colorName` stored in the Label model.
enum LabelColor: String, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case gray

    /// SwiftUI Color for rendering chips, dots, and other label indicators.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}
