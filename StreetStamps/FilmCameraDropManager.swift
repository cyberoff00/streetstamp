import Foundation

// =======================================================
// MARK: - Film Camera Drop Manager
// Per-journey film camera: drops from top to center when
// journey first starts, then stays in sidebar for the
// rest of the journey session.
// =======================================================

final class FilmCameraDropManager: ObservableObject {
    private enum StoredOutcome: String {
        case suppressed
        case centerPending
        case sidebar
    }

    enum Phase: Equatable {
        case none       // Not yet triggered for this journey
        case center     // Showing in center of screen (just dropped)
        case sidebar    // Dismissed to sidebar (above camera icon)
    }

    private static let everUnlockedKeyBase = "streetstamps.film_camera.ever_unlocked.v1"
    private static let journeyOutcomeKeyBase = "streetstamps.film_camera.journey_outcome.v1"

    @Published private(set) var phase: Phase = .none

    private let defaults: UserDefaults
    private let randomRoll: () -> Bool
    private let scheduleCenterDrop: (@escaping @MainActor () -> Void) -> Void
    private var currentJourneyID: String?

    init(
        defaults: UserDefaults = .standard,
        randomRoll: @escaping () -> Bool = { Double.random(in: 0..<1) < 0.5 },
        scheduleCenterDrop: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Task { @MainActor in action() }
            }
        }
    ) {
        self.defaults = defaults
        self.randomRoll = randomRoll
        self.scheduleCenterDrop = scheduleCenterDrop
    }

    /// Call when MapView appears during active tracking.
    /// Each journey rolls independently. Historic unlock only affects
    /// whether a successful roll lands in the center or sidebar.
    @MainActor
    func dropForJourney(journeyID: String) {
        currentJourneyID = journeyID

        switch storedOutcome(for: journeyID) {
        case .suppressed:
            phase = .none
        case .sidebar:
            if phase == .none {
                phase = .sidebar
            }
        case .centerPending:
            scheduleCenterDropIfNeeded(for: journeyID)
        case nil:
            guard randomRoll() else {
                saveStoredOutcome(.suppressed, for: journeyID)
                phase = .none
                return
            }

            if hasEverUnlocked {
                saveStoredOutcome(.sidebar, for: journeyID)
                phase = .sidebar
            } else {
                saveStoredOutcome(.centerPending, for: journeyID)
                scheduleCenterDropIfNeeded(for: journeyID)
            }
        }
    }

    /// User tapped "试试" or "一会儿再试" — move to sidebar.
    @MainActor
    func dismissToSidebar() {
        if let currentJourneyID {
            saveStoredOutcome(.sidebar, for: currentJourneyID)
        }
        phase = .sidebar
    }

    /// Reset transient presentation when MapView disappears.
    @MainActor
    func reset() {
        phase = .none
        currentJourneyID = nil
    }

    private var hasEverUnlocked: Bool {
        defaults.bool(forKey: scopedEverUnlockedKey())
    }

    private func markEverUnlocked() {
        defaults.set(true, forKey: scopedEverUnlockedKey())
    }

    private func storedOutcome(for journeyID: String) -> StoredOutcome? {
        guard let rawValue = defaults.string(forKey: scopedJourneyOutcomeKey(for: journeyID)) else {
            return nil
        }
        return StoredOutcome(rawValue: rawValue)
    }

    private func saveStoredOutcome(_ outcome: StoredOutcome, for journeyID: String) {
        defaults.set(outcome.rawValue, forKey: scopedJourneyOutcomeKey(for: journeyID))
    }

    @MainActor
    private func scheduleCenterDropIfNeeded(for journeyID: String) {
        guard phase == .none else { return }
        scheduleCenterDrop { [weak self] in
            guard let self else { return }
            guard self.currentJourneyID == journeyID, self.phase == .none else { return }
            self.markEverUnlocked()
            self.saveStoredOutcome(.sidebar, for: journeyID)
            self.phase = .center
        }
    }

    private func scopedEverUnlockedKey() -> String {
        if let userID = UserScopedProfileStateStore.activeLocalProfileID(defaults: defaults) {
            return "\(Self.everUnlockedKeyBase).user.\(userID)"
        }
        return Self.everUnlockedKeyBase
    }

    private func scopedJourneyOutcomeKey(for journeyID: String) -> String {
        if let userID = UserScopedProfileStateStore.activeLocalProfileID(defaults: defaults) {
            return "\(Self.journeyOutcomeKeyBase).user.\(userID).journey.\(journeyID)"
        }
        return "\(Self.journeyOutcomeKeyBase).journey.\(journeyID)"
    }
}
