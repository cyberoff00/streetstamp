import SwiftUI

struct DebugUserPathView: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var journeyStore: JourneyStore
    @State private var directories: [String] = []
    @State private var currentPath = ""

    var body: some View {
        List {
            Section("当前用户信息") {
                Text("activeLocalProfileID: \(sessionStore.activeLocalProfileID)")
                Text("guestID: \(sessionStore.guestID)")
                Text("accountUserID: \(sessionStore.accountUserID ?? "无")")
                Text("isLoggedIn: \(sessionStore.isLoggedIn ? "是" : "否")")
            }

            Section("当前数据路径") {
                Text(currentPath)
                    .font(.system(size: 10, design: .monospaced))
            }

            Section("旅程数量") {
                Text("加载的旅程: \(journeyStore.journeys.count)")
            }

            Section("所有用户目录") {
                ForEach(directories, id: \.self) { dir in
                    Text(dir)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
        }
        .navigationTitle("路径诊断")
        .onAppear {
            loadInfo()
        }
    }

    private func loadInfo() {
        let paths = StoragePath(userID: sessionStore.activeLocalProfileID)
        currentPath = paths.journeysDir.path

        let fm = FileManager.default
        let usersRoot = paths.userRoot.deletingLastPathComponent()

        if let entries = try? fm.contentsOfDirectory(
            at: usersRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            directories = entries.compactMap { url in
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                return url.lastPathComponent
            }.sorted()
        }
    }
}
