import SwiftUI

enum SettingsDataRepairVisibility {
    static func isAvailable(receiptLastPathComponent: String?) -> Bool {
        true
    }
}

extension SettingsView {
    @ViewBuilder
    var dataRepairSection: some View {
        if shouldShowInternalDataRepair {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("数据修复")

                Button {
                    repairCurrentUserData()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("修复当前设备数据")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(FigmaTheme.text)

                            Text("仅修复当前用户目录的索引与缓存，不影响其他用户")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if isRepairingData {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(FigmaTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(isRepairingData)
            }
            .alert("修复结果", isPresented: $showRepairMessage) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(repairMessage)
            }
        }
    }

    var shouldShowInternalDataRepair: Bool {
        SettingsDataRepairVisibility.isAvailable(
            receiptLastPathComponent: Bundle.main.appStoreReceiptURL?.lastPathComponent
        )
    }

    @MainActor
    func repairCurrentUserData() {
        isRepairingData = true

        Task {
            do {
                let userID = sessionStore.activeLocalProfileID
                let paths = StoragePath(userID: userID)
                let result = try await ManualDeviceRepairService.repairAllDeviceData(
                    activeLocalProfileID: userID,
                    currentGuestScopedUserID: sessionStore.currentGuestScopedUserID,
                    currentAccountUserID: sessionStore.accountUserID
                )

                journeyStore.rebind(paths: paths)
                cityCache.rebind(paths: paths)
                await journeyStore.loadAsync()
                cityCache.rebuildFromJourneyStore()

                isRepairingData = false
                repairMessage = """
                已修复当前用户数据。
                扫描来源 \(result.scannedSourceUserIDs.count) 个
                补回旅程 \(result.importedJourneyIDs.count) 个
                重建语义 \(result.rebuiltSemanticJourneyIDs.count) 个
                跳过已删除旅程 \(result.skippedDeletedJourneyIDs.count) 个
                """
                showRepairMessage = true
            } catch {
                isRepairingData = false
                repairMessage = "修复失败：\(error.localizedDescription)"
                showRepairMessage = true
            }
        }
    }
}
