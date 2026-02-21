/*
//
//  RobotAvatar.swift
//  StreetStamps
//
//  Created by Claire Yang on 18/01/2026.
//

import Foundation
import SwiftUI

// MARK: - Facing

enum RobotFace: String, CaseIterable {
    case front, right, back, left
}

func robotFaceFromHeading(_ headingDegrees: Double) -> RobotFace {
    let h = (headingDegrees.truncatingRemainder(dividingBy: 360) + 360)
        .truncatingRemainder(dividingBy: 360)

    switch h {
    case 45..<135:  return .right
    case 135..<225: return .back
    case 225..<315: return .left
    default:        return .front
    }
}

// MARK: - Loadout (v1: empty equipment)

struct RobotLoadout: Equatable {
    var baseId: String = "default"
    // v1: all equipment empty
    var headgearId: String? = nil
    var handheldId: String? = nil
    var backId: String? = nil
    var feetId: String? = nil
    var skinId: String? = nil
}

// MARK: - Renderer (Image Asset Based)

struct RobotRendererView: View {
    let size: CGFloat
    let face: RobotFace
    let loadout: RobotLoadout

    var body: some View {
        ZStack {
            // Base body (required)
            Image("base_\(loadout.baseId)_\(face.rawValue)")
                .resizable()
                .interpolation(.none)   // pixel art crisp
                .scaledToFit()

            // v1: equipment is empty; keep these hooks for later
            // Example:
            // if let headgear = loadout.headgearId {
            //     Image("headgear_\(headgear)_\(face.rawValue)")
            //         .resizable()
            //         .interpolation(.none)
            //         .scaledToFit()
            // }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size * 0.10, x: 0, y: size * 0.08)
        .accessibilityLabel(L10n.key("accessibility_avatar"))
    }
}

*/
