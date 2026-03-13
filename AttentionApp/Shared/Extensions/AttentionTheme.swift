import SwiftUI

// MARK: - Brand Colors

extension Color {
    static let attentionPrimary = Color(hex: "#6366F1")       // Indigo 500
    static let attentionSecondary = Color(hex: "#8B5CF6")     // Violet 500
    static let attentionAccent = Color(hex: "#EC4899")        // Pink 500
    static let attentionSuccess = Color(hex: "#10B981")       // Emerald 500
    static let attentionWarning = Color(hex: "#F59E0B")       // Amber 500
    static let attentionDanger = Color(hex: "#EF4444")        // Red 500

    // Sidebar item colors (Things 3-inspired)
    static let sidebarInbox = Color(hex: "#3B82F6")           // Blue
    static let sidebarToday = Color(hex: "#FBBF24")           // Yellow/Gold
    static let sidebarUpcoming = Color(hex: "#EF4444")        // Red
    static let sidebarAnytime = Color(hex: "#6366F1")         // Indigo
    static let sidebarSomeday = Color(hex: "#F97316")         // Orange
    static let sidebarLogbook = Color(hex: "#10B981")         // Green

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Animation Constants

enum AttentionAnimation {
    static let springDefault = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let springSnappy = Animation.spring(response: 0.25, dampingFraction: 0.75)
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let springGentle = Animation.spring(response: 0.5, dampingFraction: 0.9)

    static let fadeIn = Animation.easeIn(duration: 0.15)
    static let fadeOut = Animation.easeOut(duration: 0.12)

    static let completionDelay: Double = 0.6  // Delay before completed item disappears
}

// MARK: - Layout Constants

enum AttentionLayout {
    static let sidebarWidth: CGFloat = 240
    static let listMinWidth: CGFloat = 300
    static let detailMinWidth: CGFloat = 350

    static let cornerRadius: CGFloat = 10
    static let smallCornerRadius: CGFloat = 6

    static let padding: CGFloat = 16
    static let smallPadding: CGFloat = 8
    static let tinyPadding: CGFloat = 4

    static let iconSize: CGFloat = 20
    static let checkboxSize: CGFloat = 22
    static let tagHeight: CGFloat = 22
}

// MARK: - Checkbox Style

struct AttentionCheckboxStyle: ToggleStyle {
    var priority: Priority = .none

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(AttentionAnimation.springSnappy) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(borderColor(for: priority), lineWidth: 1.5)
                    .frame(width: AttentionLayout.checkboxSize, height: AttentionLayout.checkboxSize)

                if configuration.isOn {
                    Circle()
                        .fill(borderColor(for: priority))
                        .frame(width: AttentionLayout.checkboxSize, height: AttentionLayout.checkboxSize)
                        .transition(.scale.combined(with: .opacity))

                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func borderColor(for priority: Priority) -> Color {
        switch priority {
        case .none: .secondary.opacity(0.5)
        case .low: .blue
        case .medium: .orange
        case .high: Color.attentionDanger
        }
    }
}
