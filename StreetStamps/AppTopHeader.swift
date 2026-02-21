//
//  AppTopHeader.swift
//  StreetStamps
//

import SwiftUI

/// Unified top header used across pages.
/// - Left: hamburger entry (aligned & sized consistently)
/// - Title: single line, uppercase, same font, auto-scales to fit on all devices
struct AppTopHeader: View {
    let title: String
    @Binding var showSidebar: Bool
    private let buttonSize: CGFloat = 42

    var body: some View {
        ZStack {
            Text(title.uppercased())
                .appHeaderStyle()
                .multilineTextAlignment(.center)
                .allowsTightening(true)

            HStack(spacing: 12) {
                SidebarHamburgerButton(showSidebar: $showSidebar, size: buttonSize, iconSize: 20)

                Spacer(minLength: 0)

                Color.clear
                    .frame(width: buttonSize, height: buttonSize)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(FigmaTheme.card.opacity(0.9))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FigmaTheme.border)
                .frame(height: 1)
        }
    }
}

struct SidebarHamburgerButton: View {
    @Binding var showSidebar: Bool
    var size: CGFloat = 42
    var iconSize: CGFloat = 20
    var iconWeight: Font.Weight = .semibold
    var foreground: Color = FigmaTheme.text

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                showSidebar = true
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: iconSize, weight: iconWeight))
                .foregroundColor(foreground)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(SidebarHamburgerPressStyle())
    }
}

private struct SidebarHamburgerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.black.opacity(configuration.isPressed ? 0.10 : 0.0))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
