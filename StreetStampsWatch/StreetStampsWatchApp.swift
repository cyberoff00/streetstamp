import SwiftUI

@main
struct StreetStampsWatchApp: App {
    @StateObject private var recorder = WatchJourneyRecorder()
    @StateObject private var avatarSync = WatchAvatarSyncStore()

    var body: some Scene {
        WindowGroup {
            WatchTrackingView(recorder: recorder, avatarSync: avatarSync)
        }
    }
}

private enum WatchTheme {
    static let background = Color(red: 251.0 / 255.0, green: 251.0 / 255.0, blue: 249.0 / 255.0)
    static let accent = Color(red: 82.0 / 255.0, green: 183.0 / 255.0, blue: 136.0 / 255.0)
    static let ink = Color.black.opacity(0.88)
    static let sub = Color.black.opacity(0.56)
}

struct WatchTrackingView: View {
    @ObservedObject var recorder: WatchJourneyRecorder
    @ObservedObject var avatarSync: WatchAvatarSyncStore

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            ZStack {
                WatchTheme.background.ignoresSafeArea()

                VStack(spacing: 8) {
                    Text(recorder.elapsedText(now: context.date))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.ink)

                    Text(String(format: "%.2f km", max(0, recorder.distanceMeters) / 1000.0))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(WatchTheme.sub)

                    Group {
                        if recorder.state == .idle {
                            Button(action: primaryAction) {
                                avatarCircle
                            }
                            .buttonStyle(.plain)
                        } else {
                            avatarCircle
                        }
                    }

                    if recorder.state == .idle {
                        Text(NSLocalizedString("watch_start", comment: ""))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(WatchTheme.ink)
                    } else {
                        HStack(spacing: 8) {
                            Button(action: pauseOrResume) {
                                Text(recorder.state == .recording ? NSLocalizedString("watch_pause", comment: "") : NSLocalizedString("watch_resume", comment: ""))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(WatchTheme.accent)

                            Button(action: endAction) {
                                Text(NSLocalizedString("watch_end", comment: ""))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(WatchTheme.accent)
                        }
                    }

                    if !recorder.statusText.isEmpty {
                        Text(recorder.statusText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchTheme.sub)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            .onAppear {
                recorder.handleTimerTick(now: context.date)
            }
            .onChange(of: context.date) { _, newDate in
                recorder.handleTimerTick(now: newDate)
            }
            .alert(NSLocalizedString("watch_inactivity_title", comment: ""), isPresented: $recorder.inactivityAlertPresented) {
                Button(NSLocalizedString("watch_continue", comment: "")) {
                    recorder.continueAfterInactivityAlert()
                }
                Button(NSLocalizedString("watch_pause", comment: "")) {
                    recorder.pauseFromInactivityAlert()
                }
                Button(NSLocalizedString("watch_remind_30m", comment: "")) {
                    recorder.snoozeInactivityAlert()
                }
            } message: {
                Text(recorder.inactivityAlertMessage)
            }
        }
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(WatchTheme.accent)
            Circle()
                .stroke(Color.white.opacity(0.34), lineWidth: 2)

            WatchAvatarRendererView(loadout: avatarSync.loadout)
                .frame(width: 72, height: 72)
        }
        .frame(width: 116, height: 116)
    }

    private func primaryAction() {
        guard recorder.state == .idle else { return }
        recorder.start()
    }

    private func pauseOrResume() {
        switch recorder.state {
        case .recording:
            recorder.pause()
        case .paused:
            recorder.resume()
        case .idle:
            break
        }
    }

    private func endAction() {
        guard recorder.state != .idle else { return }
        recorder.end()
    }
}
