import SwiftUI

enum DebugFriendProfilePreviewState: String, CaseIterable, Identifiable {
    case standing
    case seated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standing:
            return "未坐下"
        case .seated:
            return "已坐下"
        }
    }

    func sceneState() -> ProfileSceneInteractionState {
        ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: self == .seated,
            isInteractionInFlight: false
        )
    }
}

struct DebugFriendProfilePreviewFixture {
    let friend: FriendProfileSnapshot

    static func make() -> DebugFriendProfilePreviewFixture {
        let cities = [
            FriendCityCard(id: "tokyo|jp", name: "Tokyo", countryISO2: "JP"),
            FriendCityCard(id: "seoul|kr", name: "Seoul", countryISO2: "KR"),
            FriendCityCard(id: "hong-kong|hk", name: "Hong Kong", countryISO2: "HK")
        ]

        let journeys = [
            FriendSharedJourney(
                id: "debug-tokyo-night",
                title: "Tokyo",
                activityTag: "Night Walk",
                overallMemory: "Shibuya neon and ramen stop",
                distance: 12_400,
                startTime: Calendar.current.date(byAdding: .day, value: -12, to: Date()),
                endTime: Calendar.current.date(byAdding: .day, value: -12, to: Date())?.addingTimeInterval(2 * 3600),
                visibility: .friendsOnly,
                routeCoordinates: [
                    CoordinateCodable(lat: 35.6595, lon: 139.7005),
                    CoordinateCodable(lat: 35.6717, lon: 139.7640),
                    CoordinateCodable(lat: 35.6895, lon: 139.6917)
                ],
                memories: [
                    FriendSharedMemory(
                        id: "debug-memory-1",
                        title: "Late ramen",
                        notes: "Tiny counter shop after the crossing.",
                        timestamp: Calendar.current.date(byAdding: .day, value: -12, to: Date()) ?? Date(),
                        imageURLs: []
                    ),
                    FriendSharedMemory(
                        id: "debug-memory-2",
                        title: "Arcade floor",
                        notes: "Blue light, loud synth, zero sense of time.",
                        timestamp: Calendar.current.date(byAdding: .day, value: -11, to: Date()) ?? Date(),
                        imageURLs: []
                    )
                ]
            ),
            FriendSharedJourney(
                id: "debug-seoul-river",
                title: "Seoul",
                activityTag: "River Ride",
                overallMemory: "Han river breeze and sunset bridge lights",
                distance: 8_200,
                startTime: Calendar.current.date(byAdding: .day, value: -4, to: Date()),
                endTime: Calendar.current.date(byAdding: .day, value: -4, to: Date())?.addingTimeInterval(90 * 60),
                visibility: .public,
                routeCoordinates: [
                    CoordinateCodable(lat: 37.5207, lon: 126.9396),
                    CoordinateCodable(lat: 37.5280, lon: 126.9326),
                    CoordinateCodable(lat: 37.5345, lon: 126.9470)
                ],
                memories: [
                    FriendSharedMemory(
                        id: "debug-memory-3",
                        title: "Bridge glow",
                        notes: "The river turned silver right before sunset.",
                        timestamp: Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date(),
                        imageURLs: []
                    )
                ]
            )
        ]

        let stats = ProfileStatsSnapshot(
            totalJourneys: journeys.count,
            totalDistance: journeys.reduce(0) { $0 + $1.distance },
            totalMemories: journeys.reduce(0) { $0 + $1.memories.count },
            totalUnlockedCities: cities.count
        )

        return DebugFriendProfilePreviewFixture(
            friend: FriendProfileSnapshot(
                id: "debug-friend-mika",
                handle: "mika.horizon",
                inviteCode: "MIKA2026",
                profileVisibility: .friendsOnly,
                displayName: "Mika Horizon",
                bio: "Collecting midnight walks, station stamps, and small restaurant memories.",
                loadout: .defaultBoy,
                stats: stats,
                journeys: journeys,
                unlockedCityCards: cities,
                createdAt: Calendar.current.date(byAdding: .month, value: -8, to: Date()) ?? Date()
            )
        )
    }
}

struct DebugFriendProfilePreviewView: View {
    @State private var previewState: DebugFriendProfilePreviewState = .standing

    private let fixture = DebugFriendProfilePreviewFixture.make()

    private var friend: FriendProfileSnapshot { fixture.friend }

    private var levelProgress: UserLevelProgress {
        UserLevelProgress.from(completedJourneyCount: max(0, friend.stats.totalJourneys))
    }

    private var sceneState: ProfileSceneInteractionState {
        previewState.sceneState()
    }

    private var visitorLoadout: RobotLoadout {
        AvatarLoadoutStore.load().normalizedForCurrentAvatar()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                previewControlsCard
                heroCard
                actionTiles
                postcardCard
                noteCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 36)
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .navigationTitle("Friend UI Preview")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PREVIEW STATE")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.7)
                .foregroundColor(FigmaTheme.text.opacity(0.46))

            Picker("Preview State", selection: $previewState) {
                ForEach(DebugFriendProfilePreviewState.allCases) { state in
                    Text(state.title).tag(state)
                }
            }
            .pickerStyle(.segmented)

            Text("该页面只用于看好友资料页 UI 和“坐一坐”状态，不读取好友关系，也不请求后端。")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(FigmaTheme.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .debugFriendCardStyle(radius: 30)
    }

    private var heroCard: some View {
        VStack(spacing: 0) {
            ProfileHeroTopBackdrop(topCornerRadius: 36) {
                VStack {
                    SofaProfileSceneView(
                        state: sceneState,
                        hostLoadout: friend.loadout,
                        visitorLoadout: visitorLoadout,
                        welcomeText: "Welcome!",
                        postcardPromptText: "send a postcard?"
                    )
                    .frame(maxWidth: 340)
                    .padding(.horizontal, 20)
                    .padding(.top, 26)
                    .padding(.bottom, 18)
                }
            }
            .frame(height: 340)

            VStack(spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(friend.displayName)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0))

                            ProfileHeroLevelPill(level: levelProgress.level)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 156.0 / 255.0, green: 163.0 / 255.0, blue: 175.0 / 255.0))

                            Text(String(format: "%.1f km", max(0, friend.stats.totalDistance / 1000.0)))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 156.0 / 255.0, green: 163.0 / 255.0, blue: 175.0 / 255.0))

                            Text("•")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 156.0 / 255.0, green: 163.0 / 255.0, blue: 175.0 / 255.0))

                            Text("Joined \(heroJoinedText(friend.createdAt))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 156.0 / 255.0, green: 163.0 / 255.0, blue: 175.0 / 255.0))
                        }
                    }

                    Spacer(minLength: 10)

                    VStack(spacing: 8) {
                        Button {
                            previewState = .seated
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: previewState == .seated ? "sofa.fill" : "sofa")
                                    .font(.system(size: 16, weight: .bold))
                                Text(previewState == .seated ? "已坐下" : "坐一坐")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(height: 48)
                            .padding(.horizontal, 20)
                            .background(FigmaTheme.primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(previewState == .seated)
                        .opacity(previewState == .seated ? 0.72 : 1)

                        Button("重置") {
                            previewState = .standing
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(FigmaTheme.mutedBackground)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                    }
                }

                ProfileHeroStatsCard(
                    items: [
                        ProfileHeroStatItem(id: "trips", value: "\(friend.stats.totalJourneys)", title: "TRIPS"),
                        ProfileHeroStatItem(id: "memories", value: "\(friend.stats.totalMemories)", title: "MEMORIES"),
                        ProfileHeroStatItem(id: "cities", value: "\(friend.stats.totalUnlockedCities)", title: "CITIES")
                    ]
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
        .debugFriendCardStyle(radius: 36)
    }

    private var actionTiles: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                featureTile(
                    icon: "books.vertical",
                    iconColor: FigmaTheme.primary,
                    iconBackground: FigmaTheme.primary.opacity(0.14),
                    title: "CITY LIBRARY"
                )

                featureTile(
                    icon: "book.pages",
                    iconColor: Color(red: 184 / 255, green: 148 / 255, blue: 125 / 255),
                    iconBackground: Color(red: 184 / 255, green: 148 / 255, blue: 125 / 255).opacity(0.14),
                    title: "JOURNEY MEMORY"
                )
            }

            HStack(spacing: 14) {
                featureTile(
                    icon: "figure.walk",
                    iconColor: Color(red: 67 / 255, green: 119 / 255, blue: 107 / 255),
                    iconBackground: Color(red: 67 / 255, green: 119 / 255, blue: 107 / 255).opacity(0.14),
                    title: "TRAVEL LOG"
                )

                featureTile(
                    icon: "bag.fill",
                    iconColor: Color(red: 93 / 255, green: 98 / 255, blue: 111 / 255),
                    iconBackground: Color(red: 93 / 255, green: 98 / 255, blue: 111 / 255).opacity(0.14),
                    title: "LOADOUT"
                )
            }
        }
    }

    private var postcardCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FigmaTheme.primary.opacity(0.14))
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("SEND POSTCARD")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                Text("仅预览入口样式，不发送真实明信片。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .debugFriendCardStyle(radius: 32)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MOCK DATA")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.7)
                .foregroundColor(FigmaTheme.text.opacity(0.46))

            Text("Profile: \(friend.displayName) · \(friend.handle)")
            Text("Journeys: \(friend.journeys.map(\.title).joined(separator: ", "))")
            Text("Invite Code: \(friend.inviteCode)")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(FigmaTheme.subtext)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .debugFriendCardStyle(radius: 30)
    }

    private func featureTile(icon: String, iconColor: Color, iconBackground: Color, title: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(iconBackground)
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                }

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 136)
        .padding(.vertical, 8)
        .debugFriendCardStyle(radius: 32)
    }

    private func heroJoinedText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: date)
    }
}

private extension View {
    func debugFriendCardStyle(radius: CGFloat) -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 8)
    }
}
