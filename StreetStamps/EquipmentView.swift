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

    private let itemPrice = 200

    var body: some View {
        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                VStack(spacing: 20) {
                    segmentRow
                    avatarPreviewCard
                    categoryRow
                    itemGrid
                }
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }

            if let feedbackMessage {
                VStack {
                    Text(feedbackMessage)
                        .font(.system(size: AppTypography.captionSize, weight: .black))
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

    private var header: some View {
        ZStack {
            Text(L10n.t("equipment_title").uppercased())
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
                        .foregroundColor(.black)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)

                    Text("\(economy.coins)")
                        .font(.system(size: AppTypography.captionSize, weight: .black))
                        .foregroundColor(.black)

                    Button {
                        showCoinPurchaseDialog = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(FigmaTheme.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color.white.opacity(0.9))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
        }
    }

    private var segmentRow: some View {
        HStack(spacing: 16) {
            segmentButton(title: L10n.t("equipment_title").uppercased(), segment: .myGear)
            segmentButton(title: "SHOP GEAR", segment: .shopGear)
        }
    }

    private func segmentButton(title: String, segment: EquipmentSegment) -> some View {
        let isActive = activeSegment == segment

        return Button {
            activeSegment = segment
        } label: {
            Text(title)
                .font(.system(size: AppTypography.bodySize, weight: .black))
                .tracking(-0.2)
                .foregroundColor(isActive ? .white : Color(red: 139.0 / 255.0, green: 139.0 / 255.0, blue: 139.0 / 255.0))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(isActive ? Color.black : Color.clear)
                        .shadow(color: isActive ? Color.black.opacity(0.15) : .clear, radius: 12, x: 0, y: 6)
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

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.catalog.categories) { cat in
                    let selected = selectedCategoryId == cat.id
                    Button {
                        selectedCategoryId = cat.id
                    } label: {
                        Text(L10n.t(cat.titleKey).uppercased())
                            .font(.system(size: AppTypography.captionSize, weight: .black))
                            .tracking(-0.2)
                            .foregroundColor(selected ? .white : Color(red: 139.0 / 255.0, green: 139.0 / 255.0, blue: 139.0 / 255.0))
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(selected ? FigmaTheme.primary : .white)
                                    .shadow(
                                        color: selected ? FigmaTheme.primary.opacity(0.25) : Color.black.opacity(0.04),
                                        radius: selected ? 10 : 8,
                                        x: 0,
                                        y: 3
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

            ScrollView(showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(visibleItems) { item in
                        let ownership = ownershipState(category: category, item: item)

                        Button {
                            handleTap(category: category, item: item, ownership: ownership)
                        } label: {
                            GearCard(
                                title: L10n.t(item.nameKey).uppercased(),
                                imageName: store.imageName(item.images, face: .front),
                                ownership: ownership,
                                mode: activeSegment,
                                price: itemPrice
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(height: 290)
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
                    itemName: L10n.t(item.nameKey).uppercased()
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
    let title: String
    let imageName: String?
    let ownership: GearOwnership
    let mode: EquipmentSegment
    let price: Int

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color(red: 216.0 / 255.0, green: 240.0 / 255.0, blue: 227.0 / 255.0))

                if let imageName {
                    Image(imageName)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(16)
                        .opacity(ownership == .locked ? 0.55 : 1)
                } else {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FigmaTheme.subtext)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if ownership == .locked {
                    pill(text: "LOCKED", fill: Color.black.opacity(0.7), textColor: .white)
                        .padding(.top, 10)
                        .padding(.leading, 10)
                }
            }
            .frame(height: 104)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 10, weight: .black))
                    .tracking(-0.2)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                actionPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 3)
    }

    @ViewBuilder
    private var actionPill: some View {
        switch mode {
        case .myGear:
            switch ownership {
            case .equipped:
                pill(
                    text: "EQUIPPED",
                    fill: Color(red: 232.0 / 255.0, green: 232.0 / 255.0, blue: 232.0 / 255.0),
                    textColor: FigmaTheme.subtext
                )
            case .owned:
                pill(
                    text: "OWNED",
                    fill: Color(red: 243.0 / 255.0, green: 243.0 / 255.0, blue: 243.0 / 255.0),
                    textColor: FigmaTheme.subtext
                )
            case .locked:
                pill(
                    text: "UNLOCK IN SHOP",
                    fill: Color.black.opacity(0.82),
                    textColor: .white
                )
            }

        case .shopGear:
            switch ownership {
            case .equipped:
                pill(text: "EQUIPPED", fill: FigmaTheme.primary, textColor: .white)
            case .owned:
                pill(
                    text: "EQUIP",
                    fill: Color(red: 232.0 / 255.0, green: 232.0 / 255.0, blue: 232.0 / 255.0),
                    textColor: FigmaTheme.subtext
                )
            case .locked:
                pill(text: "BUY \(price)", fill: Color.black, textColor: .white)
            }
        }
    }

    private func pill(text: String, fill: Color, textColor: Color) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: .black))
            .tracking(0.4)
            .foregroundColor(textColor)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Capsule().fill(fill))
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
