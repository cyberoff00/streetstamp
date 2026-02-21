import SwiftUI
import MapKit
import UIKit

enum MapAppearanceStyle: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Day"
        }
    }
}

enum MapAppearanceSettings {
    static let storageKey = "streetstamps.map.appearance"

    static func resolved(from raw: String?) -> MapAppearanceStyle {
        MapAppearanceStyle(rawValue: raw ?? "") ?? .dark
    }

    static var current: MapAppearanceStyle {
        let raw = UserDefaults.standard.string(forKey: storageKey)
        return resolved(from: raw)
    }

    static func apply(_ style: MapAppearanceStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: storageKey)
    }

    static var mapType: MKMapType {
        mapType(for: current)
    }

    static func mapType(for style: MapAppearanceStyle) -> MKMapType {
        switch style {
        case .dark: return .mutedStandard
        case .light: return .standard
        }
    }

    static func mapType(for raw: String?) -> MKMapType {
        mapType(for: resolved(from: raw))
    }

    static var interfaceStyle: UIUserInterfaceStyle {
        interfaceStyle(for: current)
    }

    static func interfaceStyle(for style: MapAppearanceStyle) -> UIUserInterfaceStyle {
        switch style {
        case .dark: return .dark
        case .light: return .light
        }
    }

    static func interfaceStyle(for raw: String?) -> UIUserInterfaceStyle {
        interfaceStyle(for: resolved(from: raw))
    }

    static var routeBaseColor: UIColor {
        routeBaseColor(for: current)
    }

    static func routeBaseColor(for style: MapAppearanceStyle) -> UIColor {
        switch style {
        case .dark:
            return UIColor(red: 221.0 / 255.0, green: 247.0 / 255.0, blue: 161.0 / 255.0, alpha: 1.0)
        case .light:
            return UIColor(red: 214.0 / 255.0, green: 109.0 / 255.0, blue: 34.0 / 255.0, alpha: 1.0)
        }
    }

    static func routeBaseColor(for raw: String?) -> UIColor {
        routeBaseColor(for: resolved(from: raw))
    }

    static var routeCoreColorForSnapshot: UIColor {
        routeCoreColorForSnapshot(for: current)
    }

    static func routeCoreColorForSnapshot(for style: MapAppearanceStyle) -> UIColor {
        switch style {
        case .dark:
            return routeBaseColor(for: style).withAlphaComponent(0.78)
        case .light:
            return routeBaseColor(for: style).withAlphaComponent(1.0)
        }
    }

    static func routeCoreColorForSnapshot(for raw: String?) -> UIColor {
        routeCoreColorForSnapshot(for: resolved(from: raw))
    }

    static var routeCoreWidthForSnapshot: CGFloat {
        routeCoreWidthForSnapshot(for: current)
    }

    static func routeCoreWidthForSnapshot(for style: MapAppearanceStyle) -> CGFloat {
        switch style {
        case .dark: return 5
        case .light: return 6
        }
    }

    static func routeCoreWidthForSnapshot(for raw: String?) -> CGFloat {
        routeCoreWidthForSnapshot(for: resolved(from: raw))
    }
}

struct ThemePalette {
    let accent: Color
    let accentLight: Color
    let accentMedium: Color
    let accentSoft: Color
}

enum ThemeStyle: String, CaseIterable, Identifiable {
    case cocoa = "cocoa"
    case spring = "spring"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cocoa:
            return "Cocoa Brown"
        case .spring:
            return "Spring Green"
        }
    }

    var hexCode: String {
        switch self {
        case .cocoa:
            return "#AD6717"
        case .spring:
            return "#05BF4C"
        }
    }

    var palette: ThemePalette {
        let base = Color(hex: hexCode)
        return ThemePalette(
            accent: base,
            accentLight: base.opacity(0.15),
            accentMedium: base.opacity(0.25),
            accentSoft: base.opacity(0.08)
        )
    }
}

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private let key = "streetstamps.theme.style"

    @Published private(set) var selectedTheme: ThemeStyle

    private init() {
        if
            let raw = UserDefaults.standard.string(forKey: key),
            let style = ThemeStyle(rawValue: raw)
        {
            selectedTheme = style
        } else {
            selectedTheme = .cocoa
        }
    }

    var currentPalette: ThemePalette {
        selectedTheme.palette
    }

    func apply(_ style: ThemeStyle) {
        guard selectedTheme != style else { return }
        selectedTheme = style
        UserDefaults.standard.set(style.rawValue, forKey: key)
    }
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        let expanded: String
        if sanitized.count == 3 {
            expanded = sanitized.map { "\($0)\($0)" }.joined()
        } else {
            expanded = sanitized
        }
        let value = UInt64(expanded, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1
        )
    }
}
