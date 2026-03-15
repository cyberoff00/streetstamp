import SwiftUI

struct LocalizationDebugView: View {
    @State private var logs: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("本地化调试日志")
                    .font(.headline)
                    .padding(.bottom, 8)

                Button("运行诊断") {
                    runDiagnostics()
                }
                .buttonStyle(.borderedProminent)

                Divider()

                ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.vertical, 2)
                }
            }
            .padding()
        }
        .onAppear {
            runDiagnostics()
        }
    }

    private func runDiagnostics() {
        logs.removeAll()

        // 1. 系统语言设置
        log("=== 系统语言设置 ===")
        log("当前 Locale: \(Locale.current.identifier)")
        log("语言代码: \(Locale.current.languageCode ?? "nil")")
        log("区域代码: \(Locale.current.regionCode ?? "nil")")
        log("首选语言: \(Locale.preferredLanguages.prefix(3).joined(separator: ", "))")

        // 2. Bundle 本地化
        log("\n=== Bundle 本地化 ===")
        log("Main bundle localizations: \(Bundle.main.localizations.joined(separator: ", "))")
        log("Preferred localizations: \(Bundle.main.preferredLocalizations.joined(separator: ", "))")

        // 3. 测试关键字符串
        log("\n=== 测试关键字符串 ===")
        let testKeys = ["start", "pause", "close", "tab_start", "tab_cities"]
        for key in testKeys {
            let value = NSLocalizedString(key, comment: "")
            let matched = value != key ? "✅" : "❌"
            log("\(matched) \(key) = \(value)")
        }

        // 4. 检查 .lproj 文件
        log("\n=== .lproj 文件检查 ===")
        let locales = ["en", "zh-Hans", "ja"]
        for locale in locales {
            if let path = Bundle.main.path(forResource: locale, ofType: "lproj") {
                log("✅ \(locale).lproj 存在: \(path)")

                // 检查 Localizable.strings
                let stringsPath = (path as NSString).appendingPathComponent("Localizable.strings")
                if FileManager.default.fileExists(atPath: stringsPath) {
                    log("  ✅ Localizable.strings 存在")

                    // 尝试加载
                    if let bundle = Bundle(path: path),
                       let dict = NSDictionary(contentsOfFile: stringsPath) {
                        log("  ✅ 可以加载，包含 \(dict.count) 个键")
                    } else {
                        log("  ❌ 无法加载 Localizable.strings")
                    }
                } else {
                    log("  ❌ Localizable.strings 不存在")
                }
            } else {
                log("❌ \(locale).lproj 不存在")
            }
        }

        // 5. 测试 L10n 辅助函数
        log("\n=== L10n 辅助函数测试 ===")
        let l10nTest = L10n.t("start")
        log("L10n.t(\"start\") = \(l10nTest)")

        // 6. 测试特定 locale
        log("\n=== 强制 locale 测试 ===")
        let zhLocale = Locale(identifier: "zh-Hans")
        let zhValue = L10n.t("start", locale: zhLocale)
        log("L10n.t(\"start\", locale: zh-Hans) = \(zhValue)")

        let enLocale = Locale(identifier: "en")
        let enValue = L10n.t("start", locale: enLocale)
        log("L10n.t(\"start\", locale: en) = \(enValue)")
    }

    private func log(_ message: String) {
        logs.append(message)
        print("🔍 \(message)")
    }
}

#Preview {
    LocalizationDebugView()
}
