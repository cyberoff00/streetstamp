import Foundation

@MainActor
final class OnboardingGuideStore: ObservableObject {
    enum Step: Int, CaseIterable {
        case startJourney
        case recordMemory
        case finishJourney
        case saveJourney
        case openCityCards
        case openJourneysSegment
        case openMemory

        var message: String {
            switch self {
            case .startJourney:
                return "点击开始旅程，先完成一次完整主线。"
            case .recordMemory:
                return "记录一条笔记，留下第一条 Memory。"
            case .finishJourney:
                return "点击完成旅程，结束这段轨迹。"
            case .saveJourney:
                return "保存旅程，生成并保存 Journey 卡片。"
            case .openCityCards:
                return "前往城市卡区域，查看解锁结果。"
            case .openJourneysSegment:
                return "切到 Journeys，确认旅程已进入集合。"
            case .openMemory:
                return "回到 Memory，确认记忆内容已沉淀。"
            }
        }

        var actionTitle: String {
            switch self {
            case .startJourney: return "开始旅程"
            case .recordMemory: return "记录笔记"
            case .finishJourney: return "完成旅程"
            case .saveJourney: return "保存旅程"
            case .openCityCards: return "去城市卡"
            case .openJourneysSegment: return "看 Journeys"
            case .openMemory: return "去 Memory"
            }
        }
    }

    enum Status: String {
        case active
        case paused
        case completed
        case skipped
    }

    enum Tip: String, CaseIterable {
        case mapLocateButton
        case mapCaptureButton
        case mapMemoryPin
        case saveCardImage
        case saveJourneyName
        case saveActivityTag
    }

    enum Hint: String, CaseIterable {
        case startFirstJourney
        case mapModeExplain
        case mapMemoryIcon
        case mapFinish
        case visibilityToggle
        case journeySavedToMemory
        case cityCardCollect
        // Tooltip-guided multi-step hints
        case memoryDetailTour
        case lifelogTour
        case friendsTour
    }

    @Published private(set) var currentStep: Step?
    @Published private(set) var status: Status = .active

    var isActive: Bool { status == .active && currentStep != nil }
    var canResume: Bool { status == .paused && currentStep != nil }
    var isFinished: Bool { status == .completed || status == .skipped }

    let defaults: UserDefaults
    private let initializedKey = "streetstamps.onboarding.v1.initialized"
    private let stepKey = "streetstamps.onboarding.v1.step"
    private let statusKey = "streetstamps.onboarding.v1.status"
    private let lightweightTipsKey = "streetstamps.onboarding.v2.lightweightTips"
    private let hintsKey = "streetstamps.onboarding.v3.hints"
    private let hintsSchemaKey = "streetstamps.onboarding.v3.schema"
    private static let currentHintsSchema = 2
    private var shownLightweightTips: Set<String> = []
    private var shownHints: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func startIfNeeded() {
        // Deprecated: step-based onboarding is intentionally disabled.
    }

    func isCurrent(_ step: Step) -> Bool {
        // Deprecated: step-based onboarding is intentionally disabled.
        false
    }

    func advance(_ expected: Step) {
        // Deprecated: step-based onboarding is intentionally disabled.
    }

    func pauseForLater() {
        // Deprecated: step-based onboarding is intentionally disabled.
    }

    func resume() {
        // Deprecated: step-based onboarding is intentionally disabled.
    }

    func skipAll() {
        // Deprecated: step-based onboarding is intentionally disabled.
    }

    func shouldShowTip(_ tip: Tip) -> Bool {
        !shownLightweightTips.contains(tip.rawValue)
    }

    func dismissTip(_ tip: Tip) {
        guard !shownLightweightTips.contains(tip.rawValue) else { return }
        shownLightweightTips.insert(tip.rawValue)
        persistLightweightTips()
    }

    func shouldShowHint(_ hint: Hint) -> Bool {
        !shownHints.contains(hint.rawValue)
    }

    func dismissHint(_ hint: Hint) {
        guard !shownHints.contains(hint.rawValue) else { return }
        shownHints.insert(hint.rawValue)
        persistHints()
    }

    private func moveNext() {
        guard let step = currentStep else { return }
        if let next = Step(rawValue: step.rawValue + 1) {
            currentStep = next
            status = .active
        } else {
            currentStep = nil
            status = .completed
        }
        persist()
    }

    private func load() {
        // Keep old keys as completed to avoid presenting legacy onboarding again.
        currentStep = nil
        status = .completed
        defaults.set(true, forKey: initializedKey)
        defaults.removeObject(forKey: stepKey)
        defaults.set(Status.completed.rawValue, forKey: statusKey)

        if let values = defaults.array(forKey: lightweightTipsKey) as? [String] {
            shownLightweightTips = Set(values)
        } else {
            shownLightweightTips = []
        }

        if let values = defaults.array(forKey: hintsKey) as? [String] {
            shownHints = Set(values)
        } else {
            shownHints = []
        }

        migrateHintsSchemaIfNeeded()
    }

    /// Called once from StreetStampsApp after JourneyStore finishes loading.
    /// Journey data is the ground truth for "has used the app before" —
    /// it doesn't depend on any onboarding-related UserDefaults keys,
    /// so it correctly identifies beta testers who installed before the
    /// onboarding system was added.
    func markExistingUserIfNeeded(hasJourneys: Bool) {
        guard hasJourneys else { return }
        autoSkipTourHints()
        // Stamp schema so future migrations don't re-run
        defaults.set(Self.currentHintsSchema, forKey: hintsSchemaKey)
    }

    /// Schema-based migration for users who already have onboarding state.
    /// This catches users who went through prior schema versions.
    private func migrateHintsSchemaIfNeeded() {
        let saved = defaults.integer(forKey: hintsSchemaKey)
        guard saved < Self.currentHintsSchema else { return }
        defer { defaults.set(Self.currentHintsSchema, forKey: hintsSchemaKey) }

        // Anyone at schema ≥ 1 ran a prior migration — definitely not new.
        if saved >= 1 {
            autoSkipTourHints()
            return
        }

        // Schema 0: could be genuinely new OR a beta user with no prior
        // onboarding keys. Check for any onboarding state as a signal.
        // The definitive check (hasJourneys) happens later via
        // markExistingUserIfNeeded() after JourneyStore loads.
        let hasOnboardingState = defaults.object(forKey: hintsKey) != nil
            || defaults.object(forKey: lightweightTipsKey) != nil
        if hasOnboardingState {
            autoSkipTourHints()
        }
    }

    private func autoSkipTourHints() {
        let toursToSkip: [Hint] = [.friendsTour, .lifelogTour, .memoryDetailTour]
        var changed = false
        for hint in toursToSkip {
            if !shownHints.contains(hint.rawValue) {
                shownHints.insert(hint.rawValue)
                changed = true
            }
        }
        if changed { persistHints() }
    }

    private func persist() {
        if let step = currentStep {
            defaults.set(step.rawValue, forKey: stepKey)
        } else {
            defaults.removeObject(forKey: stepKey)
        }
        defaults.set(status.rawValue, forKey: statusKey)
    }

    private func persistLightweightTips() {
        defaults.set(Array(shownLightweightTips), forKey: lightweightTipsKey)
    }

    private func persistHints() {
        defaults.set(Array(shownHints), forKey: hintsKey)
    }
}
