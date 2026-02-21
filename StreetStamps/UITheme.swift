//
//  UITheme.swift
//  StreetStamps
//
//  Created by Claire Yang on 16/01/2026.
//

import SwiftUI

enum UITheme {
    // Figma base background #FBFBF9
    static let bg = FigmaTheme.background
    static let pageTop = FigmaTheme.background
    static let pageMid = FigmaTheme.background
    static let pageBottom = FigmaTheme.mutedBackground
    static let pageGradient = LinearGradient(
        colors: [pageTop, pageMid, pageBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static var accent: Color { FigmaTheme.primary }
    static var accentLight: Color { FigmaTheme.primary.opacity(0.15) }
    static var accentMedium: Color { FigmaTheme.primary.opacity(0.25) }
    static var accentSoft: Color { FigmaTheme.primary.opacity(0.08) }
    
    // Legacy aliases (for compatibility)
    static var green: Color { accent }
    static var greenText: Color { accent }

    // Neutral layers
    static let softBlack = Color.black.opacity(0.92)
    static let subText = FigmaTheme.subtext
    static let hairline = FigmaTheme.border
    static let chipBg = Color.black.opacity(0.05)
    static let iconBtnBg = Color.black.opacity(0.03)

    // Card
    static let cardBg = FigmaTheme.card
    static let cardStroke = FigmaTheme.border
    static let cardSoftBorder = Color.white.opacity(0.6)
    static let cardShadow = Color.black.opacity(0.10)
    
    // Rarity colors for equipment
    static let rarityCommon = Color.black.opacity(0.5)
    static var rarityRare: Color { accent }
}
