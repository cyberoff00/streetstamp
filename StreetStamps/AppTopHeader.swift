//
//  AppTopHeader.swift
//  StreetStamps
//

import SwiftUI

enum NavigationHeaderLeadingAccessory: Equatable {
    case none
    case menu
    case back
}

enum NavigationTitleLevel: Equatable {
    case primary
    case secondary
}

struct NavigationChrome: Equatable {
    let title: String
    let leadingAccessory: NavigationHeaderLeadingAccessory
    var titleLevel: NavigationTitleLevel = .secondary
}

/// Unified top header used by main tab root pages.
/// Guarantees consistent title typography and header height.
struct UnifiedTabPageHeader<Leading: View, Trailing: View>: View {
    let title: String
    var titleLevel: NavigationTitleLevel = .primary
    var horizontalPadding: CGFloat = 18
    var topPadding: CGFloat = 14
    var bottomPadding: CGFloat = 12
    private let leading: Leading
    private let trailing: Trailing

    init(
        title: String,
        titleLevel: NavigationTitleLevel = .primary,
        horizontalPadding: CGFloat = 18,
        topPadding: CGFloat = 14,
        bottomPadding: CGFloat = 12,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.titleLevel = titleLevel
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: 42, height: 42)

            Spacer(minLength: 0)

            Text(title)
                .navigationTitleStyle(level: titleLevel)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)

            trailing
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .background(FigmaTheme.card.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FigmaTheme.border)
                .frame(height: 1)
        }
    }
}

struct UnifiedNavigationHeader<Trailing: View>: View {
    let chrome: NavigationChrome
    var horizontalPadding: CGFloat = 18
    var topPadding: CGFloat = 14
    var bottomPadding: CGFloat = 12
    var onLeadingTap: (() -> Void)? = nil
    private let trailing: Trailing

    init(
        chrome: NavigationChrome,
        horizontalPadding: CGFloat = 18,
        topPadding: CGFloat = 14,
        bottomPadding: CGFloat = 12,
        onLeadingTap: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.chrome = chrome
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.onLeadingTap = onLeadingTap
        self.trailing = trailing()
    }

    var body: some View {
        UnifiedTabPageHeader(
            title: chrome.title,
            titleLevel: chrome.titleLevel,
            horizontalPadding: horizontalPadding,
            topPadding: topPadding,
            bottomPadding: bottomPadding
        ) {
            leadingControl
        } trailing: {
            trailing
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        switch chrome.leadingAccessory {
        case .none:
            Color.clear
        case .menu:
            Button(action: { onLeadingTap?() }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(SidebarHamburgerPressStyle())
            .disabled(onLeadingTap == nil)
        case .back:
            Button(action: { onLeadingTap?() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(SidebarHamburgerPressStyle())
            .disabled(onLeadingTap == nil)
        }
    }
}

/// Unified header for primary tab pages (Home/Friends/Profile/Lifelog).
/// Keeps title centered with symmetric left/right slots.
struct MainTabHeader: View {
    let title: String
    var rightAccessory: (() -> AnyView)? = nil
    var topPadding: CGFloat = 8
    var horizontalPadding: CGFloat = 18

    var body: some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(width: 42, height: 42)

            Spacer()

            Text(title)
                .navigationTitleStyle(level: .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer()

            if let rightAccessory {
                rightAccessory()
                    .frame(width: 42, height: 42)
            } else {
                Color.clear
                    .frame(width: 42, height: 42)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, 12)
        .background(FigmaTheme.card.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FigmaTheme.border)
                .frame(height: 1)
        }
    }
}

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
                .navigationTitleStyle(level: .primary)
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

extension View {
    func navigationTitleStyle(level: NavigationTitleLevel) -> some View {
        let font: Font
        switch level {
        case .primary:
            font = .system(size: AppTypography.headerSize, weight: .bold)
        case .secondary:
            font = .system(size: AppTypography.titleSize, weight: .medium)
        }

        return self
            .font(font)
            .foregroundColor(FigmaTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}
