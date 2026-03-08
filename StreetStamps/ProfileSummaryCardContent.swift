import Foundation

struct ProfileSummaryCardContent: Equatable {
    let level: Int
    let cityCount: Int
    let memoryCount: Int

    var levelText: String {
        "Lv.\(level)"
    }

    var statsText: String {
        "\(cityCount) Cities  \(memoryCount) Memories"
    }
}
