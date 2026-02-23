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

fileprivate enum EquipmentSegment {
    case myGear
    case shopGear
}

struct EquipmentView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var loadout: RobotLoadout
    @ObservedObject private var store: AvatarCatalogStore = .shared

    @State private var selectedCategoryId: String = "hair"
    @State private var activeSegment: EquipmentSegment = .myGear
    @State private var economy: EquipmentEconomy = EquipmentEconomyStore.load()

    @State private var showCoinPurchaseDialog = false
    @State private var showInsufficientCoinsAlert = false
    @State private var showPurchaseConfirmAlert = false
    @State private var pendingPurchase: PendingPurchase?
    @State private var feedbackMessage: String?
    @State private var isSkinToneExpanded = false
    @State private var isHairColorExpanded = false

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
                segmentRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 18) {
                        avatarPreviewCard
                        categoryIconRow

                        if selectedCategoryId == "expression" {
                            skinToneCard
                        }

                        if selectedCategoryId == "hair" {
                            hairColorCard
                        }

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
    }

    private var selectedHairColorHex: String {
        normalizedHex(loadout.hairColorHex, fallback: RobotLoadout.defaultHairColorHex)
    }

    private var selectedBodyColorHex: String {
        normalizedHex(loadout.bodyColorHex, fallback: RobotLoadout.defaultBodyColorHex)
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

    private var segmentRow: some View {
        HStack(spacing: 6) {
            segmentButton(title: L10n.t("equipment_title"), segment: .myGear)
            segmentButton(title: L10n.t("equipment_shop_gear"), segment: .shopGear)
        }
        .padding(4)
        .background(Color.white.opacity(0.88))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
    }

    private func segmentButton(title: String, segment: EquipmentSegment) -> some View {
        let isActive = activeSegment == segment

        return Button {
            activeSegment = segment
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isActive ? FigmaTheme.text : FigmaTheme.subtext)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    Capsule()
                        .fill(isActive ? FigmaTheme.primary.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? FigmaTheme.primary.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var avatarPreviewCard: some View {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
            .fill(Color(red: 216.0 / 255.0, green: 240.0 / 255.0, blue: 227.0 / 255.0))
            .frame(height: 216)
            .overlay {
                RobotRendererView(size: 176, face: .front, loadout: loadout)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 24, x: 0, y: 6)
    }

    private var skinToneCard: some View {
        colorPickerCard(
            title: "Skin Tone",
            symbol: "paintpalette",
            selectedHex: selectedBodyColorHex,
            isExpanded: isSkinToneExpanded,
            colors: bodyColorOptions
        ) { hex in
            loadout.bodyColorHex = hex.uppercased()
        } onToggle: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSkinToneExpanded.toggle()
            }
        }
    }

    private var hairColorCard: some View {
        colorPickerCard(
            title: "Hair Color",
            symbol: "paintpalette",
            selectedHex: selectedHairColorHex,
            isExpanded: isHairColorExpanded,
            colors: hairColorOptions
        ) { hex in
            loadout.hairColorHex = hex.uppercased()
        } onToggle: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isHairColorExpanded.toggle()
            }
        }
    }

    private var orderedCategories: [GearCategory] {
        let map = Dictionary(uniqueKeysWithValues: store.catalog.categories.map { ($0.id, $0) })
        let preferred = ["expression", "hair", "outfit", "accessory"]
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
                        selectedCategoryId = cat.id
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

    private func colorPickerCard(
        title: String,
        symbol: String,
        selectedHex: String,
        isExpanded: Bool,
        colors: [String],
        onSelect: @escaping (String) -> Void,
        onToggle: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(FigmaTheme.primary)

                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundColor(FigmaTheme.text)

                    Spacer(minLength: 12)

                    Circle()
                        .fill(Color(hexRGB: selectedHex, fallback: .white))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            if isExpanded {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
    }

    private func categorySymbol(for categoryId: String) -> String {
        switch categoryId {
        case "expression":
            return "face.smiling"
        case "hair":
            return "person.crop.circle"
        case "outfit":
            return "tshirt"
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
            let visibleItems = category.items.filter { item in
                let ownership = ownershipState(category: category, item: item)
                if activeSegment == .myGear {
                    return ownership != .locked
                }
                return true
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(visibleItems) { item in
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
        switch activeSegment {
        case .myGear:
            switch ownership {
            case .equipped:
                break
            case .owned:
                applySelection(category: category, item: item)
                showFeedback("Equipped")
            case .locked:
                activeSegment = .shopGear
                showFeedback("Item is locked. Go unlock it in Shop Gear.")
            }

        case .shopGear:
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

    private func isSelected(category: GearCategory, item: GearItem) -> Bool {
        switch category.selectionKey {
        case "hairId":
            return loadout.hairId == item.id
        case "outfitId":
            return loadout.outfitId == item.id
        case "accessoryId":
            if item.id == "none" { return loadout.accessoryId == nil }
            return loadout.accessoryId == item.id
        case "expressionId":
            return loadout.expressionId == item.id
        default:
            return false
        }
    }

    private func applySelection(category: GearCategory, item: GearItem) {
        switch category.selectionKey {
        case "hairId":
            loadout.hairId = item.id
        case "outfitId":
            loadout.outfitId = item.id
        case "accessoryId":
            loadout.accessoryId = (item.id == "none") ? nil : item.id
        case "expressionId":
            loadout.expressionId = item.id
        default:
            break
        }
    }
}

private struct PendingPurchase: Equatable {
    let categoryId: String
    let itemId: String
    let itemName: String
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
        markOwned(categoryId: "outfit", itemId: loadout.outfitId)
        markOwned(categoryId: "expression", itemId: loadout.expressionId)
        markOwned(categoryId: "accessory", itemId: "none")

        if let accessoryId = loadout.accessoryId {
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
        case "outfitId":
            return loadout.outfitId
        case "accessoryId":
            return loadout.accessoryId
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
