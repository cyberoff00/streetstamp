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

    @Published private(set) var currentStep: Step?
    @Published private(set) var status: Status = .active

    var isActive: Bool { status == .active && currentStep != nil }
    var canResume: Bool { status == .paused && currentStep != nil }
    var isFinished: Bool { status == .completed || status == .skipped }

    private let defaults: UserDefaults
    private let initializedKey = "streetstamps.onboarding.v1.initialized"
    private let stepKey = "streetstamps.onboarding.v1.step"
    private let statusKey = "streetstamps.onboarding.v1.status"
    private let lightweightTipsKey = "streetstamps.onboarding.v2.lightweightTips"
    private var shownLightweightTips: Set<String> = []

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
}
