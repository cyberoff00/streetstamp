import SwiftUI

/// Lazily-shown banner used by social refresh paths.
///
/// UX contract:
/// - Never shown for fast operations — only appears after `delaySeconds`
///   (default 5s) of an in-flight operation. Most successful refreshes finish
///   well within that window even on shaky networks (BackendAPIClient now
///   retries transient failures internally).
/// - On success: hidden immediately so the user sees no error UI.
/// - On failure: kept visible — the wording is "still trying", not "failed".
///   The user can pull-to-refresh again at any time.
@MainActor
final class RetryBannerCoordinator: ObservableObject {
    @Published private(set) var isShowing = false
    private var lazyTask: Task<Void, Never>?

    func beginOperation(delaySeconds: TimeInterval = 5) {
        lazyTask?.cancel()
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.isShowing = true
        }
        lazyTask = task
    }

    func operationSucceeded() {
        lazyTask?.cancel()
        lazyTask = nil
        isShowing = false
    }

    /// Failure deliberately does not hide the banner — if it's already
    /// visible the user sees we're still trying; if it's not visible yet the
    /// pending lazy task is cancelled, so it stays hidden.
    func operationFailed() {
        lazyTask?.cancel()
        lazyTask = nil
    }
}

private struct NetworkRetryBannerView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text(L10n.t("network_unstable_retrying"))
                .font(.footnote)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.78))
        .clipShape(Capsule())
        .padding(.top, 8)
        .shadow(radius: 6, y: 2)
        .accessibilityLabel(L10n.t("network_unstable_retrying"))
    }
}

extension View {
    /// Overlay a "network unstable, retrying" banner at the top of the view
    /// when `isPresented` is true. Animates in/out; non-blocking; safe to use
    /// alongside navigation bars (sits below the safe-area top inset).
    func networkRetryBanner(isPresented: Bool) -> some View {
        overlay(alignment: .top) {
            if isPresented {
                NetworkRetryBannerView()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }
}
