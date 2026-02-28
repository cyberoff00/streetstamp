//
//  EquipmentView.swift
//  StreetStamps
//
//  Data-driven equipment screen (powered by AvatarCatalog.json).
//  Add new gear by updating JSON + adding images to Assets.xcassets.
//
//  Created by Claire Yang on 06/02/2026.
//

import SwiftUI

struct EquipmentView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var loadout: RobotLoadout
    @ObservedObject private var store: AvatarCatalogStore = .shared

    @State private var selectedCategoryId: String = "hair"
    @State private var isTryOnMode = false
    @State private var tryOnLoadout: RobotLoadout? = nil
    @State private var economy: EquipmentEconomy = EquipmentEconomyStore.load()

    @State private var showCoinPurchaseDialog = false
    @State private var showInsufficientCoinsAlert = false
    @State private var showPurchaseConfirmAlert = false
    @State private var showTryOnPurchaseDialog = false
    @State private var pendingPurchase: PendingPurchase?
    @State private var pendingTryOnPurchase: TryOnPurchasePlan?
    @State private var feedbackMessage: String?
    @State private var expandedColorCategoryId: String?

    private let itemPrice = 200
    private let hairColorOptions = [
        // Classic tones
        "#2B2A28", // natural black (default)
        "#3A2A1F", // dark brown
        "#5C3C2A", // chestnut
        "#8B5E3C", // light brown
        "#C8945B", // honey brown
        "#E3BE8A", // golden blonde
        // Trend tones
        "#A8ADB7", // ash gray
        "#C8D0DB", // silver blonde
        "#B28DFF", // lavender
        "#5AA2FF", // denim blue
        "#F17BAA", // rose pink
        "#C04747"  // wine red
    ]
    private let bodyColorOptions = ["#F6D7BF", "#EDC39F", "#E0AE87", "#CF956F", "#B87B57", "#915B3E"]

    var body: some View {
        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tryOnRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 18) {
                        avatarPreviewCard
                        categoryIconRow

                        inlineColorFilterPanel

                        itemGrid
                    }
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
            }

            if let feedbackMessage {
                VStack {
                    Text(feedbackMessage)
                        .font(.system(size: AppTypography.captionSize, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.88))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.top, 90)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if store.catalog.categories.first(where: { $0.id == selectedCategoryId }) == nil {
                selectedCategoryId = store.catalog.categories.first?.id ?? "hair"
            }
            economy.bootstrapIfNeeded(catalog: store.catalog, loadout: loadout)
            EquipmentEconomyStore.save(economy)
        }
        .onChange(of: loadout) { _, newValue in
            AvatarLoadoutStore.save(newValue)
            economy.ensureCurrentLoadoutOwned(loadout: newValue)
        }
        .onChange(of: isTryOnMode) { _, enabled in
            if !enabled {
                tryOnLoadout = nil
            }
        }
        .onChange(of: economy) { _, newValue in
            EquipmentEconomyStore.save(newValue)
        }
        .confirmationDialog(L10n.t("buy_coins"), isPresented: $showCoinPurchaseDialog, titleVisibility: .visible) {
            Button(L10n.t("add_200_coins")) { addCoins(200) }
            Button(L10n.t("add_1000_coins")) { addCoins(1000) }
            Button(L10n.t("add_5000_coins")) { addCoins(5000) }
            Button(L10n.t("cancel"), role: .cancel) { }
        }
        .alert(L10n.t("not_enough_coins"), isPresented: $showInsufficientCoinsAlert) {
            Button(L10n.t("add_1000"), role: .none) {
                addCoins(1000)
            }
            Button(L10n.t("cancel"), role: .cancel) { }
        } message: {
            Text(String(format: L10n.t("need_coins_to_unlock"), itemPrice))
        }
        .alert(L10n.t("confirm_purchase"), isPresented: $showPurchaseConfirmAlert) {
            Button(String(format: L10n.t("buy_n_coins"), itemPrice), role: .none) {
                confirmPendingPurchase()
            }
            Button(L10n.t("cancel"), role: .cancel) {
                pendingPurchase = nil
            }
        } message: {
            Text(purchaseConfirmMessage)
        }
        .overlay {
            if showTryOnPurchaseDialog {
                tryOnPurchaseDialog
            }
        }
    }

    private var effectiveLoadout: RobotLoadout {
        tryOnLoadout ?? loadout
    }

    private var selectedHairColorHex: String {
        normalizedHex(effectiveLoadout.hairColorHex, fallback: RobotLoadout.defaultHairColorHex)
    }

    private var selectedBodyColorHex: String {
        normalizedHex(effectiveLoadout.bodyColorHex, fallback: RobotLoadout.defaultBodyColorHex)
    }

    private func normalizedHex(_ raw: String, fallback: String) -> String {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !normalized.hasPrefix("#") {
            normalized = "#\(normalized)"
        }
        if normalized.count == 7 {
            return normalized
        }
        return fallback.uppercased()
    }

    private var header: some View {
        ZStack {
            Text(L10n.t("equipment_title"))
                .appHeaderStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 80)

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.system(size: AppTypography.captionSize, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)

                    Text("\(economy.coins)")
                        .font(.system(size: AppTypography.captionSize, weight: .semibold))
                        .foregroundColor(FigmaTheme.text)

                    Button {
                        showCoinPurchaseDialog = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: AppTypography.bodySize, weight: .bold))
                            .foregroundColor(FigmaTheme.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(FigmaTheme.border, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(FigmaTheme.card.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FigmaTheme.border)
                .frame(height: 1)
        }
        .zIndex(2)
    }

    private var tryOnRow: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $isTryOnMode) {
                Text("试穿模式")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
            }
            .toggleStyle(.switch)

            Spacer()

            if isTryOnMode, let tryOnLoadout, tryOnLoadout != loadout {
                Button("应用试穿") {
                    let missing = missingItemsForTryOn(loadout: tryOnLoadout)
                    guard !missing.isEmpty else {
                        loadout = tryOnLoadout
                        self.tryOnLoadout = nil
                        isTryOnMode = false
                        showFeedback("已应用")
                        return
                    }
                    pendingTryOnPurchase = TryOnPurchasePlan(targetLoadout: tryOnLoadout, missingItems: missing)
                    showTryOnPurchaseDialog = true
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(FigmaTheme.primary.opacity(0.16))
                .clipShape(Capsule())
                .buttonStyle(.plain)

                Button("取消") {
                    self.tryOnLoadout = nil
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.06))
                .clipShape(Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.88))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
    }

    private var avatarPreviewCard: some View {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
            .fill(Color(red: 216.0 / 255.0, green: 240.0 / 255.0, blue: 227.0 / 255.0))
            .frame(height: 216)
            .overlay {
                RobotRendererView(size: 176, face: .front, loadout: effectiveLoadout)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 24, x: 0, y: 6)
    }

    @ViewBuilder
    private var inlineColorFilterPanel: some View {
        switch expandedColorCategoryId {
        case "expression":
            compactColorSwatches(colors: bodyColorOptions, selectedHex: selectedBodyColorHex) { hex in
                updateLoadout {
                    $0.bodyColorHex = hex.uppercased()
                }
            }
        case "hair":
            compactColorSwatches(colors: hairColorOptions, selectedHex: selectedHairColorHex) { hex in
                updateLoadout {
                    $0.hairColorHex = hex.uppercased()
                }
            }
        default:
            EmptyView()
        }
    }

    private var orderedCategories: [GearCategory] {
        let map = Dictionary(uniqueKeysWithValues: store.catalog.categories.map { ($0.id, $0) })
        let preferred = ["expression", "hair", "suit", "upper", "under", "accessory"]
        let preferredItems = preferred.compactMap { map[$0] }
        let rest = store.catalog.categories.filter { !preferred.contains($0.id) }
        return preferredItems + rest
    }

    private var categoryIconRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(orderedCategories) { cat in
                    let selected = selectedCategoryId == cat.id
                    Button {
                        let isColorCategory = cat.id == "expression" || cat.id == "hair"
                        let isSameCategory = selectedCategoryId == cat.id
                        selectedCategoryId = cat.id

                        guard isColorCategory else {
                            expandedColorCategoryId = nil
                            return
                        }

                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isSameCategory {
                                expandedColorCategoryId = (expandedColorCategoryId == cat.id) ? nil : cat.id
                            } else {
                                expandedColorCategoryId = cat.id
                            }
                        }
                    } label: {
                        Image(systemName: categorySymbol(for: cat.id))
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(selected ? FigmaTheme.primary : FigmaTheme.subtext)
                            .frame(width: 44, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected ? FigmaTheme.primary.opacity(0.16) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selected ? FigmaTheme.primary.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
    }

    private func compactColorSwatches(
        colors: [String],
        selectedHex: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 34), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(colors, id: \.self) { hex in
                colorSwatch(
                    hex: hex,
                    isSelected: selectedHex == hex.uppercased()
                ) {
                    onSelect(hex)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func categorySymbol(for categoryId: String) -> String {
        switch categoryId {
        case "expression":
            return "face.smiling"
        case "hair":
            return "person.crop.circle"
        case "suit":
            return "tshirt"
        case "upper":
            return "tshirt.fill"
        case "under":
            return "figure.walk"
        case "accessory":
            return "eyeglasses"
        default:
            return "circle.grid.2x2"
        }
    }

    private func colorSwatch(hex: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Circle()
                .fill(Color(hexRGB: hex, fallback: .white))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.black : Color.black.opacity(0.12), lineWidth: isSelected ? 2.2 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var itemGrid: some View {
        if let category = store.catalog.categories.first(where: { $0.id == selectedCategoryId }) {
            let columns = [
                GridItem(.flexible(), spacing: 10, alignment: .top),
                GridItem(.flexible(), spacing: 10, alignment: .top),
                GridItem(.flexible(), spacing: 10, alignment: .top)
            ]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(category.items) { item in
                    let ownership = ownershipState(category: category, item: item)

                    Button {
                        handleTap(category: category, item: item, ownership: ownership)
                    } label: {
                        GearCard(
                            imageName: store.imageName(item.images, face: .front),
                            isEquipped: ownership == .equipped,
                            isLocked: ownership == .locked,
                            price: itemPrice
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        } else {
            EmptyView()
        }
    }

    private func ownershipState(category: GearCategory, item: GearItem) -> GearOwnership {
        if isSelected(category: category, item: item) {
            return .equipped
        }
        if economy.owns(categoryId: category.id, itemId: item.id) {
            return .owned
        }
        return .locked
    }

    private func handleTap(category: GearCategory, item: GearItem, ownership: GearOwnership) {
        if isTryOnMode {
            applySelection(category: category, item: item)
            showFeedback("试穿中")
            return
        }

        switch ownership {
        case .equipped:
            break
        case .owned:
            applySelection(category: category, item: item)
            showFeedback("Equipped")
        case .locked:
            if economy.coins < itemPrice {
                showInsufficientCoinsAlert = true
                return
            }

            pendingPurchase = PendingPurchase(
                categoryId: category.id,
                itemId: item.id,
                itemName: L10n.t(item.nameKey)
            )
            showPurchaseConfirmAlert = true
        }
    }

    private func addCoins(_ amount: Int) {
        guard amount > 0 else { return }
        economy.coins += amount
        showFeedback("+\(amount) coins")
    }

    private func showFeedback(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            feedbackMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.2)) {
                feedbackMessage = nil
            }
        }
    }

    private var purchaseConfirmMessage: String {
        guard let pendingPurchase else { return "Unlock this item?" }
        let remaining = economy.coins - itemPrice
        return "\(pendingPurchase.itemName)\nPrice: \(itemPrice) coins\nBalance: \(economy.coins) → \(remaining)"
    }

    private func confirmPendingPurchase() {
        guard let pendingPurchase else { return }
        guard economy.coins >= itemPrice else {
            showInsufficientCoinsAlert = true
            self.pendingPurchase = nil
            return
        }
        guard
            let category = store.catalog.categories.first(where: { $0.id == pendingPurchase.categoryId }),
            let item = category.items.first(where: { $0.id == pendingPurchase.itemId })
        else {
            self.pendingPurchase = nil
            return
        }

        economy.coins -= itemPrice
        economy.markOwned(categoryId: category.id, itemId: item.id)
        applySelection(category: category, item: item)
        showFeedback("Unlocked and equipped")
        self.pendingPurchase = nil
    }

    private var pendingTryOnPurchaseCost: Int {
        guard let pendingTryOnPurchase else { return 0 }
        return pendingTryOnPurchase.missingItems.count * itemPrice
    }

    @ViewBuilder
    private var tryOnPurchaseDialog: some View {
        let items = pendingTryOnPurchase?.missingItems ?? []
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    showTryOnPurchaseDialog = false
                    pendingTryOnPurchase = nil
                }

            VStack(spacing: 14) {
                Text("未购买装备")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 56), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(items, id: \.self) { item in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 231.0 / 255.0, green: 245.0 / 255.0, blue: 236.0 / 255.0))
                            .frame(height: 56)
                            .overlay {
                                if let imageName = item.imageName {
                                    Image(imageName)
                                        .resizable()
                                        .interpolation(.none)
                                        .scaledToFit()
                                        .padding(8)
                                } else {
                                    Image(systemName: "questionmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(FigmaTheme.subtext)
                                }
                            }
                    }
                }
                .frame(maxHeight: 210)

                HStack(spacing: 6) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(FigmaTheme.primary)
                    Text("总价 \(pendingTryOnPurchaseCost)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.text)
                }

                HStack(spacing: 10) {
                    Button(L10n.t("cancel")) {
                        showTryOnPurchaseDialog = false
                        pendingTryOnPurchase = nil
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)

                    Button("一键购买并应用") {
                        confirmTryOnPurchaseAndApply()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(FigmaTheme.primary)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: 340)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(FigmaTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
        }
    }

    private func confirmTryOnPurchaseAndApply() {
        guard let pendingTryOnPurchase else { return }
        let cost = pendingTryOnPurchaseCost
        guard economy.coins >= cost else {
            showInsufficientCoinsAlert = true
            showTryOnPurchaseDialog = false
            self.pendingTryOnPurchase = nil
            return
        }

        economy.coins -= cost
        for item in pendingTryOnPurchase.missingItems {
            economy.markOwned(categoryId: item.categoryId, itemId: item.itemId)
        }

        loadout = pendingTryOnPurchase.targetLoadout
        tryOnLoadout = nil
        isTryOnMode = false
        showTryOnPurchaseDialog = false
        showFeedback("已购买并应用")
        self.pendingTryOnPurchase = nil
    }

    private func isSelected(category: GearCategory, item: GearItem) -> Bool {
        let current = effectiveLoadout
        switch category.selectionKey {
        case "hairId":
            return current.hairId == item.id
        case "suitId":
            if item.id == "none" { return current.suitId == nil }
            return current.suitId == item.id
        case "upperId":
            if item.id == "none" { return current.upperId == "none" }
            return current.upperId == item.id
        case "underId":
            if item.id == "none" { return current.underId == "none" }
            return current.underId == item.id
        case "accessoryId":
            if item.id == "none" { return current.accessoryIds.isEmpty }
            return current.accessoryIds.contains(item.id)
        case "expressionId":
            return current.expressionId == item.id
        default:
            return false
        }
    }

    private func updateLoadout(_ transform: (inout RobotLoadout) -> Void) {
        if isTryOnMode {
            var temp = tryOnLoadout ?? loadout
            transform(&temp)
            tryOnLoadout = temp
        } else {
            transform(&loadout)
        }
    }

    private func applySelection(category: GearCategory, item: GearItem) {
        updateLoadout { target in
            switch category.selectionKey {
            case "hairId":
                target.hairId = item.id
            case "suitId":
                let selectedSuit = (item.id == "none") ? nil : item.id
                if selectedSuit != nil {
                    if target.upperId != "none" {
                        target.savedUpperIdForSuit = target.upperId
                    }
                    if target.underId != "none" {
                        target.savedUnderIdForSuit = target.underId
                    }
                    target.suitId = selectedSuit
                    target.upperId = "none"
                    target.underId = "none"
                } else {
                    target.suitId = nil
                    if target.upperId == "none" {
                        target.upperId = target.savedUpperIdForSuit
                    }
                    if target.underId == "none" {
                        target.underId = target.savedUnderIdForSuit
                    }
                }
            case "upperId":
                target.upperId = item.id
                if item.id != "none" {
                    target.savedUpperIdForSuit = item.id
                    target.suitId = nil
                }
            case "underId":
                target.underId = item.id
                if item.id != "none" {
                    target.savedUnderIdForSuit = item.id
                    target.suitId = nil
                }
            case "accessoryId":
                if item.id == "none" {
                    target.accessoryIds = []
                } else {
                    if let idx = target.accessoryIds.firstIndex(of: item.id) {
                        target.accessoryIds.remove(at: idx)
                    } else {
                        target.accessoryIds.append(item.id)
                    }
                }
            case "expressionId":
                target.expressionId = item.id
            default:
                break
            }
        }
    }

    private func missingItemsForTryOn(loadout: RobotLoadout) -> [TryOnMissingItem] {
        var seen = Set<String>()
        var result: [TryOnMissingItem] = []

        func appendIfMissing(categoryId: String, itemId: String?) {
            guard let itemId, itemId != "none" else { return }
            guard !economy.owns(categoryId: categoryId, itemId: itemId) else { return }
            let key = "\(categoryId)::\(itemId)"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            let imageName = store.item(categoryId: categoryId, itemId: itemId).flatMap { store.imageName($0.images, face: .front) }
            result.append(TryOnMissingItem(categoryId: categoryId, itemId: itemId, imageName: imageName))
        }

        appendIfMissing(categoryId: "hair", itemId: loadout.hairId)
        appendIfMissing(categoryId: "expression", itemId: loadout.expressionId)
        appendIfMissing(categoryId: "suit", itemId: loadout.suitId)
        appendIfMissing(categoryId: "upper", itemId: loadout.upperId)
        appendIfMissing(categoryId: "under", itemId: loadout.underId)
        for accessoryId in loadout.accessoryIds {
            appendIfMissing(categoryId: "accessory", itemId: accessoryId)
        }
        return result
    }
}

private struct PendingPurchase: Equatable {
    let categoryId: String
    let itemId: String
    let itemName: String
}

private struct TryOnMissingItem: Equatable, Hashable {
    let categoryId: String
    let itemId: String
    let imageName: String?
}

private struct TryOnPurchasePlan: Equatable {
    let targetLoadout: RobotLoadout
    let missingItems: [TryOnMissingItem]
}

private enum GearOwnership {
    case equipped
    case owned
    case locked
}

private struct GearCard: View {
    let imageName: String?
    let isEquipped: Bool
    let isLocked: Bool
    let price: Int

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 231.0 / 255.0, green: 245.0 / 255.0, blue: 236.0 / 255.0))

                if let imageName {
                    Image(imageName)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 82, height: 82, alignment: .center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .opacity(isLocked ? 0.45 : 1)
                } else {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FigmaTheme.subtext)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 98)
            .overlay(alignment: .topLeading) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.black.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isEquipped {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(FigmaTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(8)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FigmaTheme.primary)

                Text("\(price)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

private struct EquipmentEconomy: Codable, Equatable {
    var coins: Int
    var ownedItemsByCategory: [String: [String]]

    static let startingCoins = 600

    static var empty: EquipmentEconomy {
        EquipmentEconomy(coins: startingCoins, ownedItemsByCategory: [:])
    }

    mutating func bootstrapIfNeeded(catalog: AvatarCatalog, loadout: RobotLoadout) {
        if ownedItemsByCategory.isEmpty {
            ownedItemsByCategory = [:]

            for category in catalog.categories {
                var seed = Set<String>()

                if let first = category.items.first?.id {
                    seed.insert(first)
                }
                if let equipped = equippedItemId(selectionKey: category.selectionKey, loadout: loadout) {
                    seed.insert(equipped)
                }
                if category.id == "accessory" {
                    seed.insert("none")
                }

                ownedItemsByCategory[category.id] = Array(seed)
            }

            if coins <= 0 {
                coins = Self.startingCoins
            }
        }

        ensureCurrentLoadoutOwned(loadout: loadout)
    }

    mutating func ensureCurrentLoadoutOwned(loadout: RobotLoadout) {
        markOwned(categoryId: "hair", itemId: loadout.hairId)
        markOwned(categoryId: "suit", itemId: "none")
        markOwned(categoryId: "upper", itemId: "none")
        markOwned(categoryId: "under", itemId: "none")
        if let suitId = loadout.suitId {
            markOwned(categoryId: "suit", itemId: suitId)
        }
        markOwned(categoryId: "upper", itemId: loadout.upperId)
        markOwned(categoryId: "under", itemId: loadout.underId)
        markOwned(categoryId: "expression", itemId: loadout.expressionId)
        markOwned(categoryId: "accessory", itemId: "none")

        for accessoryId in loadout.accessoryIds {
            markOwned(categoryId: "accessory", itemId: accessoryId)
        }
    }

    func owns(categoryId: String, itemId: String) -> Bool {
        guard let owned = ownedItemsByCategory[categoryId] else { return false }
        return owned.contains(itemId)
    }

    mutating func markOwned(categoryId: String, itemId: String) {
        var set = Set(ownedItemsByCategory[categoryId] ?? [])
        set.insert(itemId)
        ownedItemsByCategory[categoryId] = Array(set)
    }

    private func equippedItemId(selectionKey: String, loadout: RobotLoadout) -> String? {
        switch selectionKey {
        case "hairId":
            return loadout.hairId
        case "suitId":
            return loadout.suitId
        case "upperId":
            return loadout.upperId
        case "underId":
            return loadout.underId
        case "accessoryId":
            return loadout.accessoryIds.first
        case "expressionId":
            return loadout.expressionId
        default:
            return nil
        }
    }
}

private enum EquipmentEconomyStore {
    private static let key = "equipment.economy.v1"

    static func load() -> EquipmentEconomy {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(EquipmentEconomy.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    static func save(_ economy: EquipmentEconomy) {
        guard let data = try? JSONEncoder().encode(economy) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
