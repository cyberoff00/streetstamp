enum JourneyRouteDetailInteractionPolicy {
    enum MemoryTapDestination: Equatable {
        case editMemory
        case viewMemory
    }

    static func destinationForMemoryTap(isReadOnly: Bool) -> MemoryTapDestination {
        isReadOnly ? .viewMemory : .editMemory
    }
}
