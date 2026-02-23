import Foundation
import Combine

/// App-level flow triggers that should not be tied to any single tab/view lifecycle.
///
/// Why signals?
/// - A Bool can be missed if a view is not currently observing when it flips.
/// - An incrementing Int is a simple, reliable "edge trigger".
@MainActor
final class AppFlowCoordinator: ObservableObject {
    @Published private(set) var resumeOngoingSignal: Int = 0
    @Published private(set) var endOngoingSignal: Int = 0
    @Published private(set) var sidebarHiddenTokens: Set<String> = []

    func requestResumeOngoing() {
        resumeOngoingSignal += 1
    }

    func requestEndOngoing() {
        endOngoingSignal += 1
    }

    var shouldShowSidebarButton: Bool {
        sidebarHiddenTokens.isEmpty
    }

    func pushSidebarButtonHidden(token: String) {
        guard !token.isEmpty else { return }
        sidebarHiddenTokens.insert(token)
    }

    func popSidebarButtonHidden(token: String) {
        guard !token.isEmpty else { return }
        sidebarHiddenTokens.remove(token)
    }
}
