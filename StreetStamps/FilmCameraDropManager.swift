import Foundation

// =======================================================
// MARK: - Film Camera Drop Manager
// Per-journey film camera: drops from top to center when
// journey first starts, then stays in sidebar for the
// rest of the journey session.
// =======================================================

final class FilmCameraDropManager: ObservableObject {
    enum Phase: Equatable {
        case none       // Not yet triggered for this journey
        case center     // Showing in center of screen (just dropped)
        case sidebar    // Dismissed to sidebar (above camera icon)
    }

    @Published private(set) var phase: Phase = .none

    /// Whether the center drop has already been shown for this journey.
    /// Once shown and dismissed, subsequent MapView appearances go straight to sidebar.
    private var hasDroppedThisJourney: Bool = false

    /// Call when MapView appears during active tracking.
    /// First call: drops to center. Subsequent calls: straight to sidebar.
    func dropForJourney() {
        if hasDroppedThisJourney {
            // Re-entering MapView during same journey — go straight to sidebar
            if phase == .none {
                phase = .sidebar
            }
            return
        }

        guard phase == .none else { return }
        hasDroppedThisJourney = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.phase == .none else { return }
            self.phase = .center
        }
    }

    /// User tapped "试试" or "一会儿再试" — move to sidebar.
    func dismissToSidebar() {
        phase = .sidebar
    }

    /// Reset when journey ends (MapView disappears at finish).
    func reset() {
        phase = .none
        hasDroppedThisJourney = false
    }
}
