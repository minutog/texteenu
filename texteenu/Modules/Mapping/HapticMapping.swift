import Foundation

struct HapticInstruction: Equatable {
    let intensity: Double
}

protocol HapticMappingService {
    func instruction(for importanceIntensity: Double) -> HapticInstruction
}

struct ImportancePulseHapticMapper: HapticMappingService {
    let minimumIntensity: Double

    init(minimumIntensity: Double = 0.15) {
        self.minimumIntensity = minimumIntensity
    }

    func instruction(for importanceIntensity: Double) -> HapticInstruction {
        let clampedImportance = importanceIntensity.clampedToUnitInterval
        let intensity = minimumIntensity + ((1 - minimumIntensity) * clampedImportance)
        return HapticInstruction(intensity: intensity)
    }
}
