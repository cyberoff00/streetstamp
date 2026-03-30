import SwiftUI
import UIKit

struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SwipeBackVC { SwipeBackVC() }
    func updateUIViewController(_ uiViewController: SwipeBackVC, context: Context) {}

    final class SwipeBackVC: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

/// Defers creation of the wrapped view until it actually appears.
/// Use inside NavigationLink destinations to prevent SwiftUI from
/// eagerly evaluating heavy views and triggering re-render loops.
struct LazyNavigationView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}
