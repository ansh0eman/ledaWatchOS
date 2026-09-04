import Foundation
import HealthKit
import Observation

enum HealthMetric: String, CaseIterable {
    case activeEnergy
    case steps
    case restingHeartRate
    case heartRate
    case sleep
    case workoutMinutes
    case respiratoryRate
    case oxygenSaturation
    case heartRateVariability
    case walkingHeartRate

    var title: String {
        switch self {
        case .activeEnergy: return "ACTIVE ENERGY"
        case .steps: return "STEPS"
        case .restingHeartRate: return "RESTING HR"
        case .heartRate: return "HEART RATE"
        case .sleep: return "SLEEP"
        case .workoutMinutes: return "WORKOUT"
        case .respiratoryRate: return "RESPIRATORY"
        case .oxygenSaturation: return "BLOOD OXYGEN"
        case .heartRateVariability: return "HRV"
        case .walkingHeartRate: return "WALKING HR"
        }
    }

    var shortDescription: String {
        switch self {
        case .activeEnergy: return "Move energy burned today"
        case .steps: return "Steps recorded today"
        case .restingHeartRate: return "Latest resting heart rate"
        case .heartRate: return "Latest heart rate sample"
        case .sleep: return "Sleep recorded last night"
        case .workoutMinutes: return "Workout time today"
        case .respiratoryRate: return "Latest breaths per minute"
        case .oxygenSaturation: return "Latest oxygen saturation"
        case .heartRateVariability: return "Latest HRV (SDNN)"
        case .walkingHeartRate: return "Latest walking heart rate"
        }
    }
}

struct HealthMetricSnapshot {
    let value: String
    let unit: String
    let detail: String
}

@MainActor
@Observable
final class HealthDashboardManager {
    private let healthStore = HKHealthStore()

    private(set) var isAuthorized = false
    private(set) var isLoading = false
    private(set) var snapshot: HealthMetricSnapshot?
    private(set) var errorMessage: String?

    var healthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func load(_ metric: HealthMetric) {
        Task {
            await loadMetric(metric)
        }
    }

    func requestAccessAndLoad(_ metric: HealthMetric) {
        Task {
            do {
                try await requestAuthorizationIfNeeded()
                await loadMetric(metric)
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        guard healthDataAvailable else {
            throw HealthDashboardError.healthDataUnavailable
        }

        let types = readableTypes()

        try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: types) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthDashboardError.authorizationFailed)
                }
            }
        }

        isAuthorized = true
    }

    private func loadMetric(_ metric: HealthMetric) async {
        guard healthDataAvailable else {
            errorMessage = "Health data is unavailable on this device."
            snapshot = nil
            return
        }

        if !isAuthorized {
            do {
                try await requestAuthorizationIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
                snapshot = nil
                return
            }
        }

        isLoading = true
        errorMessage = nil

        do {
            let result: HealthMetricSnapshot?

            switch metric {
            case .activeEnergy:
                result = try await todayCumulative(
                    identifier: .activeEnergyBurned,
                    unit: .kilocalorie(),
                    formatter: { String(Int($0.rounded())) },
                    unitLabel: "KCAL"
                )

            case .steps:
                result = try await todayCumulative(
                    identifier: .stepCount,
                    unit: .count(),
                    formatter: { String(Int($0.rounded())) },
                    unitLabel: "STEPS"
                )

            case .restingHeartRate:
                result = try await latestQuantity(
                    identifier: .restingHeartRate,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    formatter: { String(Int($0.rounded())) },
                    unitLabel: "BPM"
                )

            case .heartRate:
                result = try await latestQuantity(
                    identifier: .heartRate,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    formatter: { String(Int($0.rounded())) },
                    unitLabel: "BPM"
                )

            case .sleep:
                result = try await lastNightSleep()

            case .workoutMinutes:
                result = try await workoutMinutesToday()

            case .respiratoryRate:
                result = try await latestQuantity(
                    identifier: .respiratoryRate,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    formatter: { String(format: "%.1f", $0) },
                    unitLabel: "BR/MIN"
                )

            case .oxygenSaturation:
                result = try await latestQuantity(
                    identifier: .oxygenSaturation,
                    unit: .percent(),
                    formatter: { String(Int(($0 * 100).rounded())) },
                    unitLabel: "%"
                )

            case .heartRateVariability:
                result = try await latestQuantity(
                    identifier: .heartRateVariabilitySDNN,
                    unit: .secondUnit(with: .milli),
                    formatter: { String(Int($0.rounded())) },
                    unitLabel: "MS"
                )

            case .walkingHeartRate:
                result = try await latestQuantity(
                    identifier: .walkingHeartRateAverage,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    formatter: { String(Int($0.rounded())) },
                    unitLabel: "BPM"
                )
            }

            snapshot = result
            if result == nil {
                errorMessage = "No recent data found."
            }
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func readableTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .stepCount,
            .restingHeartRate,
            .heartRate,
            .respiratoryRate,
            .oxygenSaturation,
            .heartRateVariabilitySDNN,
            .walkingHeartRateAverage,
        ]

        for identifier in quantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }

        return types
    }

    private func latestQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        formatter: @escaping (Double) -> String,
        unitLabel: String
    ) async throws -> HealthMetricSnapshot? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let sample = try await latestSample(for: type)
        guard let sample else { return nil }

        let rawValue = sample.quantity.doubleValue(for: unit)
        let relative = RelativeDateTimeFormatter().localizedString(for: sample.endDate, relativeTo: Date())

        return HealthMetricSnapshot(
            value: formatter(rawValue),
            unit: unitLabel,
            detail: relative.uppercased()
        )
    }

    private func latestSample(for type: HKQuantityType) async throws -> HKQuantitySample? {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }

            healthStore.execute(query)
        }
    }

    private func todayCumulative(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        formatter: @escaping (Double) -> String,
        unitLabel: String
    ) async throws -> HealthMetricSnapshot? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let sum = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: result?.sumQuantity())
            }

            healthStore.execute(query)
        }

        guard let sum else { return nil }
        let rawValue = sum.doubleValue(for: unit)

        return HealthMetricSnapshot(
            value: formatter(rawValue),
            unit: unitLabel,
            detail: "TODAY"
        )
    }

    private func lastNightSleep() async throws -> HealthMetricSnapshot? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: end) ?? end.addingTimeInterval(-86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }

            healthStore.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]

        let seconds = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

        guard seconds > 0 else { return nil }

        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)

        return HealthMetricSnapshot(
            value: "\(hours)H \(minutes)M",
            unit: "SLEEP",
            detail: "LAST 24 HOURS"
        )
    }

    private func workoutMinutesToday() async throws -> HealthMetricSnapshot? {
        let type = HKObjectType.workoutType()
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }

            healthStore.execute(query)
        }

        guard !workouts.isEmpty else { return nil }
        let minutes = Int((workouts.reduce(0.0) { $0 + $1.duration } / 60).rounded())

        return HealthMetricSnapshot(
            value: String(minutes),
            unit: "MIN",
            detail: "TODAY"
        )
    }
}

private enum HealthDashboardError: LocalizedError {
    case healthDataUnavailable
    case authorizationFailed

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Health data is unavailable on this device."
        case .authorizationFailed:
            return "Health access was not granted."
        }
    }
}
