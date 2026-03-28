import SwiftUI
import UIKit

struct TabSelectionHapticTracker {
    private(set) var currentIndex: Int

    mutating func sync(to index: Int) {
        currentIndex = index
    }

    mutating func shouldEmit(for newIndex: Int) -> Bool {
        guard newIndex != currentIndex else { return false }
        currentIndex = newIndex
        return true
    }
}

struct TabBarSelectionHapticObserver: UIViewControllerRepresentable {
    let currentTab: NavigationTab

    func makeCoordinator() -> Coordinator {
        Coordinator(currentIndex: currentTab.rawValue)
    }

    func makeUIViewController(context: Context) -> ObserverViewController {
        let viewController = ObserverViewController()
        viewController.onResolveTabBarController = { tabBarController in
            context.coordinator.attach(to: tabBarController)
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: ObserverViewController, context: Context) {
        context.coordinator.sync(to: currentTab.rawValue)
        uiViewController.onResolveTabBarController = { tabBarController in
            context.coordinator.attach(to: tabBarController)
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        private var tracker: TabSelectionHapticTracker
        private weak var tabBarController: UITabBarController?

        init(currentIndex: Int) {
            tracker = TabSelectionHapticTracker(currentIndex: currentIndex)
        }

        func sync(to index: Int) {
            tracker.sync(to: index)
            Haptics.prepareLight()
        }

        func attach(to tabBarController: UITabBarController) {
            guard self.tabBarController !== tabBarController else { return }
            self.tabBarController?.delegate = nil
            self.tabBarController = tabBarController
            tracker.sync(to: tabBarController.selectedIndex)
            tabBarController.delegate = self
            Haptics.prepareLight()
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let selectedIndex = tabBarController.selectedIndex
            guard tracker.shouldEmit(for: selectedIndex) else { return }
            Haptics.light()
        }
    }
}

final class ObserverViewController: UIViewController {
    var onResolveTabBarController: ((UITabBarController) -> Void)?
    private var resolved = false

    override func loadView() {
        let view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resolveTabBarControllerOnce()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        resolveTabBarControllerOnce()
    }

    private func resolveTabBarControllerOnce() {
        guard !resolved else { return }
        guard let tabBarController = sequence(first: parent, next: { $0?.parent })
            .compactMap({ $0 as? UITabBarController })
            .first else {
            return
        }
        resolved = true
        onResolveTabBarController?(tabBarController)
    }
}
