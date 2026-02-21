import Foundation
import SwiftUI
import MapKit
import CoreLocation
import Combine
import UIKit


struct  RobotLocationMarker: View {
    var size: CGFloat = 36
    var headingDegrees: Double = 0

    // MARK: - Facing

    private enum Face {
        case front, right, back, left
    }

    private var normalizedHeading: Double {
        let h = headingDegrees.truncatingRemainder(dividingBy: 360)
        return h >= 0 ? h : (h + 360)
    }

    private var face: Face {
        // 4-face snap: front(315-45), right(45-135), back(135-225), left(225-315)
        switch normalizedHeading {
        case 45..<135:  return .right
        case 135..<225: return .back
        case 225..<315: return .left
        default:        return .front
        }
    }

    private var yaw: Double {
        // Mild 3D hint for side views
        switch face {
        case .right: return 20
        case .left:  return -20
        default:     return 0
        }
    }

    // MARK: - Body

    var body: some View {
        let s = size

        ZStack {
            // Ground shadow (gives instant "standing on map" feel)
            Ellipse()
                .fill(Color.black.opacity(0.22))
                .frame(width: s * 0.95, height: s * 0.28)
                .offset(y: s * 1.05)
                .blur(radius: 3)

            // ===== Lower body (legs + feet) =====
            lowerBody(size: s)
                .offset(y: s * 0.52)

            // ===== Torso + Arms (ARMS ATTACHED HERE) =====
            torso(size: s)
                .overlay(alignment: .topLeading) {
                    arm(size: s, side: .left, face: face)
                        // Shoulder anchor relative to torso
                        .offset(x: -s * 0.28, y: s * 0.18)
                }
                .overlay(alignment: .topTrailing) {
                    arm(size: s, side: .right, face: face)
                        .offset(x: s * 0.28, y: s * 0.18)
                }
                .offset(y: s * 0.08)
                .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.75)

            // ===== Head =====
            head(size: s, face: face)
                .offset(y: -s * 0.42)
                .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.75)

            // ===== Antenna =====
            antenna(size: s)
                .offset(y: -s * 0.92)
                .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.75)
        }
        .frame(width: s * 2.1, height: s * 2.4)
        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 8)
        .accessibilityLabel(L10n.key("accessibility_you"))
    }

    // MARK: - Parts

    private func head(size s: CGFloat, face: Face) -> some View {
        ZStack {
            // Head shell (capsule-ish)
            RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.86),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.95, height: s * 0.62)
                .overlay(
                    RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 7, x: 0, y: 6)

            // Face plate / visor area
            RoundedRectangle(cornerRadius: s * 0.18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.28),
                            Color.black.opacity(0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: s * 0.74, height: s * 0.36)
                .offset(y: s * 0.02)
                .overlay(
                    // Visor highlight
                    RoundedRectangle(cornerRadius: s * 0.18, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: s * 0.62, height: s * 0.12)
                        .offset(x: -s * 0.06, y: -s * 0.06)
                        .blur(radius: 0.4)
                )

            // Eyes / back panel depending on face
            switch face {
            case .front:
                eyes(size: s, offsetX: 0, squishX: 1.0, alpha: 1.0)
            case .right:
                eyes(size: s, offsetX: s * 0.08, squishX: 0.92, alpha: 0.95)
            case .left:
                eyes(size: s, offsetX: -s * 0.08, squishX: 0.92, alpha: 0.95)
            case .back:
                // Back: service panel (prevents "empty back")
                RoundedRectangle(cornerRadius: s * 0.12, style: .continuous)
                    .fill(Color.black.opacity(0.10))
                    .frame(width: s * 0.56, height: s * 0.22)
                    .overlay(
                        HStack(spacing: s * 0.06) {
                            Circle().fill(Color.black.opacity(0.20))
                                .frame(width: s * 0.07, height: s * 0.07)
                            Circle().fill(Color.black.opacity(0.20))
                                .frame(width: s * 0.07, height: s * 0.07)
                            Circle().fill(Color.black.opacity(0.20))
                                .frame(width: s * 0.07, height: s * 0.07)
                        }
                    )
                    .offset(y: s * 0.04)
            }
        }
    }

    private func eyes(size s: CGFloat, offsetX: CGFloat, squishX: CGFloat, alpha: Double) -> some View {
        HStack(spacing: s * 0.14) {
            eye(size: s)
            eye(size: s)
        }
        .opacity(alpha)
        .scaleEffect(x: squishX, y: 1, anchor: .center)
        .offset(x: offsetX, y: s * 0.04)
    }

    private func eye(size s: CGFloat) -> some View {
        Circle()
            .fill(Color.white.opacity(0.92))
            .frame(width: s * 0.11, height: s * 0.11)
            .overlay(
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: s * 0.05, height: s * 0.05)
            )
            .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 1))
    }

    private func torso(size s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.82),
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.92, height: s * 0.78)
                .overlay(
                    RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )

            // Chest pocket/panel
            RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(width: s * 0.52, height: s * 0.20)
                .offset(y: s * 0.10)
                .overlay(
                    RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        .offset(y: s * 0.10)
                )

            // Soft highlight
            Ellipse()
                .fill(Color.white.opacity(0.26))
                .frame(width: s * 0.52, height: s * 0.22)
                .offset(x: -s * 0.18, y: -s * 0.20)
                .blur(radius: 0.6)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 7)
    }

    private enum ArmSide { case left, right }

    private func arm(size s: CGFloat, side: ArmSide, face: Face) -> some View {
        // Optional: in back view, arms look slightly tucked
        let tuck: CGFloat = (face == .back) ? 0.85 : 1.0

        return HStack(spacing: s * 0.04) {
            Capsule()
                .fill(Color.white.opacity(0.88))
                .frame(width: s * 0.20 * tuck, height: s * 0.065)
                .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))

            Capsule()
                .fill(Color.white.opacity(0.85))
                .frame(width: s * 0.18 * tuck, height: s * 0.060)
                .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))

            // Simple hand (can be replaced by handheld items later)
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: s * 0.10, height: s * 0.10)
                .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 1))
        }
        // Mirror right arm
        .scaleEffect(x: side == .right ? -1 : 1, y: 1)
        // Arms slightly droop for a "hanging" feel
        .rotationEffect(.degrees(side == .right ? -14 : 14), anchor: .leading)
    }

    private func lowerBody(size s: CGFloat) -> some View {
        ZStack {
            // Hip block
            RoundedRectangle(cornerRadius: s * 0.18, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: s * 0.78, height: s * 0.30)
                .overlay(
                    RoundedRectangle(cornerRadius: s * 0.18, style: .continuous)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 5)

            // Legs + feet
            HStack(spacing: s * 0.20) {
                leg(size: s)
                leg(size: s)
            }
            .offset(y: s * 0.26)
        }
    }

    private func leg(size s: CGFloat) -> some View {
        VStack(spacing: s * 0.06) {
            // Thigh segment
            Capsule()
                .fill(Color.white.opacity(0.88))
                .frame(width: s * 0.16, height: s * 0.20)
                .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))

            // Knee ring (gives "segmented" look)
            Capsule()
                .fill(Color.black.opacity(0.08))
                .frame(width: s * 0.18, height: s * 0.05)

            // Shin segment
            Capsule()
                .fill(Color.white.opacity(0.86))
                .frame(width: s * 0.15, height: s * 0.20)
                .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))

            // Foot
            Ellipse()
                .fill(Color.white.opacity(0.92))
                .frame(width: s * 0.32, height: s * 0.14)
                .overlay(Ellipse().stroke(Color.black.opacity(0.10), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 4)
                .offset(y: -s * 0.02)
        }
    }

    private func antenna(size s: CGFloat) -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.18))
                .frame(width: s * 0.08, height: s * 0.20)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.98), Color.black.opacity(0.10)],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: s * 0.12
                    )
                )
                .frame(width: s * 0.18, height: s * 0.18)
                .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 1))
        }
        .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 3)
    }
}

