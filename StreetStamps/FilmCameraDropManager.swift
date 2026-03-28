import Foundation

// =======================================================
// MARK: - Film Camera Drop Manager
// Manages random camera drops when user enters MapView.
// Each session entry has a chance to "find" a film camera.
// =======================================================

final class FilmCameraDropManager: ObservableObject {
    @Published private(set) var hasFilmCamera: Bool = false
    @Published var showDropAnimation: Bool = false

    /// Drop probability per MapView session.
    /// Tune this down later once the novelty factor is calibrated.
    private let dropChance: Double = 1.0

    /// Cooldown: minimum seconds between drops to avoid spam.
    /// Set to 0 during development; raise to 120–300 for production.
    private let cooldownInterval: TimeInterval = 0

    private static let lastDropKey = "FilmCamera.lastDropTimestamp"

    /// Call this when MapView appears. Rolls the dice for a camera drop.
    func rollForDrop() {
        // Already showing — don't re-trigger
        guard !hasFilmCamera else { return }

        // Check cooldown
        let lastDrop = UserDefaults.standard.double(forKey: Self.lastDropKey)
        let now = Date().timeIntervalSince1970
        guard now - lastDrop > cooldownInterval else { return }

        // Roll
        let roll = Double.random(in: 0...1)
        if roll < dropChance {
            UserDefaults.standard.set(now, forKey: Self.lastDropKey)
            // Small delay for natural feel
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.hasFilmCamera = true
                self?.showDropAnimation = true
                // Auto-dismiss animation flag
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.showDropAnimation = false
                }
            }
        }
    }

    /// Call after the user has used the camera (or dismissed it).
    /// The camera stays available for the rest of this MapView session.
    func markUsed() {
        // Camera remains available until MapView disappears.
        // No-op for now; extend if single-use is desired.
    }

    /// Reset when MapView disappears.
    func reset() {
        hasFilmCamera = false
        showDropAnimation = false
    }
}
