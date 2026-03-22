import Foundation
import CoreLocation

struct ManualDeviceRepairResult {
    let importedJourneyIDs: [String]
    let skippedDeletedJourneyIDs: [String]
    let scannedSourceUserIDs: [String]
    let rebuiltSemanticJourneyIDs: [String]
}

enum ManualDeviceRepairService {
    typealias CanonicalResolver = @Sendable (CLLocation) async -> ReverseGeocodeService.CanonicalResult?

    static func repairAllDeviceData(
        activeLocalProfileID: String,
        currentGuestScopedUserID: String,
        currentAccountUserID: String?,
        canonicalResolver: CanonicalResolver? = nil
    ) async throws -> ManualDeviceRepairResult {
        let activePaths = StoragePath(userID: activeLocalProfileID)
        try activePaths.ensureBaseDirectoriesExist()
        let resolver = canonicalResolver ?? { location in
            await canonicalResultWithRetry(for: location)
        }

        let deletedIDs = DeletedJourneyStore.load(userID: activeLocalProfileID)
        let existingIDs = Set(CurrentUserRepairDiagnostic.loadActualJourneyIDs(from: activePaths.journeysDir))
        let sourceUserIDs = discoverSourceUserIDs(
            activeLocalProfileID: activeLocalProfileID,
            currentGuestScopedUserID: currentGuestScopedUserID,
            currentAccountUserID: currentAccountUserID
        )

        var candidateImportedIDs = Set<String>()
        var skippedDeletedIDs = Set<String>()

        for sourceUserID in sourceUserIDs {
            let sourcePaths = StoragePath(userID: sourceUserID)
            let sourceIDs = Set(CurrentUserRepairDiagnostic.loadActualJourneyIDs(from: sourcePaths.journeysDir))
            let deletedMatches = sourceIDs.intersection(deletedIDs)
            skippedDeletedIDs.formUnion(deletedMatches)

            let missingAllowedIDs = sourceIDs
                .subtracting(existingIDs)
                .subtracting(deletedIDs)

            guard !missingAllowedIDs.isEmpty else { continue }

            _ = try GuestDataRecoveryService.recover(
                from: sourceUserID,
                to: activeLocalProfileID,
                options: .conservativeAuto
            )
            candidateImportedIDs.formUnion(missingAllowedIDs)
        }

        let fileStore = JourneysFileStore(baseURL: activePaths.journeysDir)
        for id in deletedIDs {
            try? fileStore.deleteJourney(id: id)
        }

        let repairedIDs = CurrentUserRepairDiagnostic
            .loadActualJourneyIDs(from: activePaths.journeysDir)
            .filter { !deletedIDs.contains($0) }

        try JourneyIndexRepairTool.rebuildIndex(
            userID: activeLocalProfileID,
            allowedJourneyIDs: repairedIDs
        )

        let rebuiltSemanticJourneyIDs = try rebuildJourneySemantics(
            journeyIDs: repairedIDs,
            fileStore: fileStore
        )
        let rebuiltCityJourneyIDs = try await rebuildJourneyCityIdentity(
            journeyIDs: repairedIDs,
            fileStore: fileStore,
            canonicalResolver: resolver
        )
        let rebuiltIDs = Set(rebuiltSemanticJourneyIDs).union(rebuiltCityJourneyIDs)

        return ManualDeviceRepairResult(
            importedJourneyIDs: candidateImportedIDs.sorted(),
            skippedDeletedJourneyIDs: skippedDeletedIDs.sorted(),
            scannedSourceUserIDs: sourceUserIDs,
            rebuiltSemanticJourneyIDs: rebuiltIDs.sorted()
        )
    }

    private static func discoverSourceUserIDs(
        activeLocalProfileID: String,
        currentGuestScopedUserID: String,
        currentAccountUserID: String?
    ) -> [String] {
        let fm = FileManager.default
        let usersRoot = StoragePath(userID: activeLocalProfileID).userRoot.deletingLastPathComponent()
        guard
            fm.fileExists(atPath: usersRoot.path),
            let entries = try? fm.contentsOfDirectory(
                at: usersRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return entries.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let userID = url.lastPathComponent
            guard userID != activeLocalProfileID else { return nil }
            guard isRecoverableSourceUserID(
                userID,
                currentGuestScopedUserID: currentGuestScopedUserID,
                currentAccountUserID: currentAccountUserID
            ) else { return nil }
            guard hasRecoverableJourneyData(userID: userID) else { return nil }
            return userID
        }
        .sorted()
    }

    private static func isRecoverableSourceUserID(
        _ userID: String,
        currentGuestScopedUserID: String,
        currentAccountUserID: String?
    ) -> Bool {
        guard !userID.hasPrefix("friend_preview_") else { return false }
        guard !userID.hasPrefix("temp_") else { return false }
        if userID == currentGuestScopedUserID {
            return true
        }
        if let currentAccountUserID, userID == "account_\(currentAccountUserID)" {
            return true
        }
        return false
    }

    private static func hasRecoverableJourneyData(userID: String) -> Bool {
        let journeysDir = StoragePath(userID: userID).journeysDir
        return !CurrentUserRepairDiagnostic.loadActualJourneyIDs(from: journeysDir).isEmpty
    }

    private static func rebuildJourneySemantics(
        journeyIDs: [String],
        fileStore: JourneysFileStore
    ) throws -> [String] {
        guard !journeyIDs.isEmpty else { return [] }

        let encoder = JSONEncoder()
        var rebuiltIDs: [String] = []

        for id in journeyIDs {
            guard let route = try? fileStore.loadJourney(id: id) else { continue }
            let updated = rebuildSemantics(for: route)
            guard
                let originalData = try? encoder.encode(route),
                let updatedData = try? encoder.encode(updated),
                originalData != updatedData
            else {
                continue
            }

            try fileStore.finalizeJourney(updated)
            rebuiltIDs.append(id)
        }

        return rebuiltIDs
    }

    private static func rebuildJourneyCityIdentity(
        journeyIDs: [String],
        fileStore: JourneysFileStore,
        canonicalResolver: @escaping CanonicalResolver
    ) async throws -> [String] {
        guard !journeyIDs.isEmpty else { return [] }

        let encoder = JSONEncoder()
        var rewrittenIDs: [String] = []

        for id in journeyIDs {
            guard let route = try? fileStore.loadJourney(id: id) else { continue }
            let updated = await rebuildCityIdentity(
                for: route,
                canonicalResolver: canonicalResolver
            )
            guard
                let originalData = try? encoder.encode(route),
                let updatedData = try? encoder.encode(updated),
                originalData != updatedData
            else {
                continue
            }

            try fileStore.finalizeJourney(updated)
            rewrittenIDs.append(id)
        }

        return rewrittenIDs
    }

    static func rebuildSemantics(for route: JourneyRoute) -> JourneyRoute {
        var updated = route
        let recordedLocations = interpolatedRecordedLocations(for: route)
        let lastKnownLocation = recordedLocations.last

        updated.memories = route.memories.map { memory in
            rebuildMemorySemantics(
                memory,
                lastKnownLocation: lastKnownLocation,
                recordedLocations: recordedLocations
            )
        }

        updated.correctedCoordinates = JourneyPostCorrection.correctedCoordinates(for: updated)
        if !updated.correctedCoordinates.isEmpty, updated.preferredRouteSource == .raw {
            updated.preferredRouteSource = .corrected
        }
        updated.distance = JourneyPostCorrection.correctedDistance(for: updated)

        return updated
    }

    static func rebuildCityIdentity(
        for route: JourneyRoute,
        canonicalResolver: @escaping CanonicalResolver
    ) async -> JourneyRoute {
        guard let startLocation = route.coordinates.first?.cl else {
            return route
        }

        let endLocation = route.coordinates.last?.cl
        let startCanonical = await canonicalResolver(CLLocation(latitude: startLocation.latitude, longitude: startLocation.longitude))
        let endCanonical: ReverseGeocodeService.CanonicalResult?
        if let endLocation {
            endCanonical = await canonicalResolver(CLLocation(latitude: endLocation.latitude, longitude: endLocation.longitude))
        } else {
            endCanonical = nil
        }

        var updated = JourneyFinalizer.resolveCompletedRouteCityFields(
            route: route,
            startCanonical: startCanonical,
            endCanonical: endCanonical
        )
        if let startCanonical {
            let stableStartKey = startCanonical.cityKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let stableStartName = CityPlacemarkResolver.stableCityName(
                from: stableStartKey,
                fallback: startCanonical.cityName
            )
            updated.cityKey = stableStartKey
            updated.startCityKey = stableStartKey
            updated.canonicalCity = stableStartName
            updated.cityName = stableStartName
            updated.currentCity = stableStartName
            updated.countryISO2 = startCanonical.iso2 ?? updated.countryISO2
            updated.memories = updated.memories.map { memory in
                var normalized = memory
                normalized.cityKey = stableStartKey
                normalized.cityName = stableStartName
                return normalized
            }
        }
        return updated
    }

    private static func rebuildMemorySemantics(
        _ memory: JourneyMemory,
        lastKnownLocation: CLLocation?,
        recordedLocations: [CLLocation]
    ) -> JourneyMemory {
        if memory.locationStatus == .pending || memory.locationSource == .pending {
            return JourneyMemoryLocationResolver.finalize(
                memory: memory,
                lastKnownLocation: lastKnownLocation,
                recordedLocations: recordedLocations
            )
        }

        guard memory.locationSource == .legacyCoordinate else { return memory }
        guard shouldBackfillLegacyMemory(memory) else { return memory }

        let resolved = JourneyMemoryLocationResolver.resolve(
            memoryTimestamp: memory.timestamp,
            liveLocation: nil,
            lastKnownLocation: lastKnownLocation,
            recordedLocations: recordedLocations
        )
        guard resolved.status != .pending else { return memory }

        var updated = memory
        updated.coordinate = resolved.coordinate
        updated.locationStatus = resolved.status
        updated.locationSource = resolved.source
        return updated
    }

    private static func shouldBackfillLegacyMemory(_ memory: JourneyMemory) -> Bool {
        let lat = memory.coordinate.0
        let lon = memory.coordinate.1
        if lat == 0, lon == 0 {
            return true
        }
        return !CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    private static func interpolatedRecordedLocations(for route: JourneyRoute) -> [CLLocation] {
        let coords = route.coordinates
        guard !coords.isEmpty else { return [] }

        return coords.enumerated().map { index, coord in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lon),
                altitude: 0,
                horizontalAccuracy: 10,
                verticalAccuracy: 10,
                timestamp: fallbackTimestamp(
                    for: index,
                    total: coords.count,
                    start: route.startTime,
                    end: route.endTime
                )
            )
        }
    }

    private static func fallbackTimestamp(
        for index: Int,
        total: Int,
        start: Date?,
        end: Date?
    ) -> Date {
        guard total > 1 else { return end ?? start ?? Date() }
        let startValue = start ?? end ?? Date()
        let endValue = end ?? startValue
        let span = max(0, endValue.timeIntervalSince(startValue))
        guard span > 0 else { return endValue }
        let t = Double(index) / Double(max(total - 1, 1))
        return startValue.addingTimeInterval(span * t)
    }

    private static func canonicalResultWithRetry(
        for location: CLLocation,
        maxAttempts: Int = 4
    ) async -> ReverseGeocodeService.CanonicalResult? {
        for attempt in 0..<maxAttempts {
            if let result = await ReverseGeocodeService.shared.canonical(for: location) {
                return result
            }
            guard attempt < maxAttempts - 1 else { break }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
        }
        return nil
    }
}
