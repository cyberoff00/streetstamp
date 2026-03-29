import SwiftUI

struct MemoryPin: View {
    let cluster: [JourneyMemory]

    var body: some View {
        let hasPhoto = cluster.contains { !$0.imagePaths.isEmpty }
        let hasNote = cluster.contains { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let count = cluster.count
        let allPending = cluster.allSatisfy { $0.locationStatus == .pending }

        ZStack {
            Circle()
                .fill(UITheme.accent)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

            ZStack {
                if allPending {
                    // Pending: GPS is resolving
                    Image(systemName: "location.slash")
                        .font(.system(size: 14, weight: .semibold))
                } else if hasPhoto && hasNote {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .offset(x: 6, y: 0)

                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .offset(x: -6, y: 0)
                } else if hasPhoto {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundColor(.black.opacity(0.75))

            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Circle().fill(Color.black))
                    .offset(x: 12, y: -12)
            }
        }
        .opacity(allPending ? 0.55 : 1.0)
    }
}
