import SwiftUI

// MARK: - Anchor Registration

/// Each target view registers its frame in the coordinate space via this key.
struct CoachMarkAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Register this view as a coach mark target. The `id` must match a `CoachMarkStep.targetID`.
    func coachMark(id: String) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CoachMarkAnchorKey.self,
                    value: [id: geo.frame(in: .named("coachMarkSpace"))]
                )
            }
        )
    }
}

// MARK: - Step Definition

/// Defines one step in a coach mark tour.
struct CoachMarkStep {
    let targetID: String
    let message: String
    var icon: String? = nil
    /// Preferred edge to place the bubble relative to the target. Auto-adjusts if not enough space.
    var preferredEdge: TooltipArrowEdge = .bottom
}

// MARK: - Tour State Persistence

extension OnboardingGuideStore {
    private static let tourStepKeyPrefix = "streetstamps.onboarding.v3.tourStep."

    /// Get the persisted step index for a tour (0-based). Returns 0 if none saved.
    func tourStepIndex(for hint: Hint) -> Int {
        defaults.integer(forKey: Self.tourStepKeyPrefix + hint.rawValue)
    }

    /// Save progress for a tour step.
    func setTourStepIndex(_ index: Int, for hint: Hint) {
        defaults.set(index, forKey: Self.tourStepKeyPrefix + hint.rawValue)
    }

    /// Clear saved tour progress (called when tour completes).
    func clearTourStep(for hint: Hint) {
        defaults.removeObject(forKey: Self.tourStepKeyPrefix + hint.rawValue)
    }
}

// MARK: - Cutout Shape

/// A shape that fills the entire rect except for a rounded-rect hole at `cutout`.
private struct CutoutShape: Shape {
    let cutout: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let hole = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: cutout)
        path.addPath(hole)
        return path
    }
}

// MARK: - Coach Mark Overlay Modifier

struct CoachMarkTourModifier: ViewModifier {
    let steps: [CoachMarkStep]
    let hint: OnboardingGuideStore.Hint
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @State private var anchors: [String: CGRect] = [:]
    @State private var showTour = false
    @State private var currentIndex = 0
    @State private var bubbleSize: CGSize = .zero

    private let cutoutPadding: CGFloat = 6
    private let cutoutCornerRadius: CGFloat = 10
    private let bubbleSpacing: CGFloat = 10
    private let bubbleMaxWidth: CGFloat = 280

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: "coachMarkSpace")
            .onPreferenceChange(CoachMarkAnchorKey.self) { anchors = $0 }
            .overlay {
                if showTour, currentIndex < steps.count {
                    let step = steps[currentIndex]
                    let targetRect = anchors[step.targetID] ?? .zero

                    GeometryReader { geo in
                        // Dim layer with cutout hole
                        ZStack {
                            if targetRect != .zero {
                                CutoutShape(
                                    cutout: targetRect.insetBy(dx: -cutoutPadding, dy: -cutoutPadding),
                                    cornerRadius: cutoutCornerRadius
                                )
                                .fill(Color.black.opacity(0.4), style: FillStyle(eoFill: true))
                                .ignoresSafeArea()
                                // Tap on dim area → advance
                                .onTapGesture { advance() }
                            } else {
                                Color.black.opacity(0.4)
                                    .ignoresSafeArea()
                                    .onTapGesture { advance() }
                            }
                        }
                        .allowsHitTesting(true)

                        // Tooltip bubble positioned relative to target
                        if targetRect != .zero {
                            let placement = computePlacement(
                                targetRect: targetRect,
                                containerSize: geo.size,
                                preferredEdge: step.preferredEdge
                            )

                            TooltipBubble(
                                message: step.message,
                                icon: step.icon,
                                arrowEdge: placement.arrowEdge,
                                stepLabel: steps.count > 1 ? "\(currentIndex + 1)/\(steps.count)" : nil,
                                actionTitle: currentIndex < steps.count - 1 ? L10n.t("tooltip_next") : L10n.t("tooltip_done"),
                                onAction: { advance() },
                                onDismiss: { dismissAll() }
                            )
                            .fixedSize()
                            .background(
                                GeometryReader { bubbleGeo in
                                    Color.clear.onAppear { bubbleSize = bubbleGeo.size }
                                        .onChange(of: currentIndex) { _ in
                                            // Reset for re-measure on step change
                                            bubbleSize = bubbleGeo.size
                                        }
                                }
                            )
                            .position(x: placement.x, y: placement.y)
                            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: currentIndex)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .onAppear {
                if onboardingGuide.shouldShowHint(hint) {
                    let savedIndex = onboardingGuide.tourStepIndex(for: hint)
                    currentIndex = min(savedIndex, steps.count - 1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                            showTour = true
                        }
                    }
                }
            }
    }

    private func advance() {
        if currentIndex < steps.count - 1 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                currentIndex += 1
            }
            onboardingGuide.setTourStepIndex(currentIndex, for: hint)
        } else {
            dismissAll()
        }
    }

    private func dismissAll() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            showTour = false
        }
        onboardingGuide.dismissHint(hint)
        onboardingGuide.clearTourStep(for: hint)
    }

    private struct Placement {
        let x: CGFloat
        let y: CGFloat
        let arrowEdge: TooltipArrowEdge
    }

    /// Compute where to place the bubble relative to the target rect.
    private func computePlacement(targetRect: CGRect, containerSize: CGSize, preferredEdge: TooltipArrowEdge) -> Placement {
        let arrowSize: CGFloat = 10
        let margin: CGFloat = 16
        // Estimate bubble size (use measured if available, else estimate)
        let bw = bubbleSize.width > 0 ? bubbleSize.width : bubbleMaxWidth
        let bh = bubbleSize.height > 0 ? bubbleSize.height : 80

        // Try preferred edge first, then fallback
        let edgesToTry: [TooltipArrowEdge] = {
            var edges: [TooltipArrowEdge] = [preferredEdge]
            for e in [TooltipArrowEdge.bottom, .top, .leading, .trailing] where e != preferredEdge {
                edges.append(e)
            }
            return edges
        }()

        for edge in edgesToTry {
            switch edge {
            case .top:
                // Bubble below target (arrow points up to target)
                let y = targetRect.maxY + cutoutPadding + arrowSize + bubbleSpacing + bh / 2
                let x = clampX(targetRect.midX, bw: bw, containerWidth: containerSize.width, margin: margin)
                if y + bh / 2 < containerSize.height - margin {
                    return Placement(x: x, y: y, arrowEdge: .top)
                }
            case .bottom:
                // Bubble above target (arrow points down to target)
                let y = targetRect.minY - cutoutPadding - arrowSize - bubbleSpacing - bh / 2
                let x = clampX(targetRect.midX, bw: bw, containerWidth: containerSize.width, margin: margin)
                if y - bh / 2 > margin {
                    return Placement(x: x, y: y, arrowEdge: .bottom)
                }
            case .leading:
                // Bubble to the right of target (arrow points left)
                let x = targetRect.maxX + cutoutPadding + arrowSize + bubbleSpacing + bw / 2
                let y = clampY(targetRect.midY, bh: bh, containerHeight: containerSize.height, margin: margin)
                if x + bw / 2 < containerSize.width - margin {
                    return Placement(x: x, y: y, arrowEdge: .leading)
                }
            case .trailing:
                // Bubble to the left of target (arrow points right)
                let x = targetRect.minX - cutoutPadding - arrowSize - bubbleSpacing - bw / 2
                let y = clampY(targetRect.midY, bh: bh, containerHeight: containerSize.height, margin: margin)
                if x - bw / 2 > margin {
                    return Placement(x: x, y: y, arrowEdge: .trailing)
                }
            }
        }

        // Ultimate fallback: center of screen
        return Placement(x: containerSize.width / 2, y: containerSize.height / 2, arrowEdge: .bottom)
    }

    private func clampX(_ ideal: CGFloat, bw: CGFloat, containerWidth: CGFloat, margin: CGFloat) -> CGFloat {
        let minX = margin + bw / 2
        let maxX = containerWidth - margin - bw / 2
        return max(minX, min(maxX, ideal))
    }

    private func clampY(_ ideal: CGFloat, bh: CGFloat, containerHeight: CGFloat, margin: CGFloat) -> CGFloat {
        let minY = margin + bh / 2
        let maxY = containerHeight - margin - bh / 2
        return max(minY, min(maxY, ideal))
    }
}

extension View {
    /// Attaches an anchor-based coach mark tour with cutout passthrough and persisted progress.
    func coachMarkTour(steps: [CoachMarkStep], hint: OnboardingGuideStore.Hint) -> some View {
        modifier(CoachMarkTourModifier(steps: steps, hint: hint))
    }
}
