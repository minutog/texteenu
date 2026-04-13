import UIKit

@MainActor
protocol HapticService: AnyObject {
    func play(_ instruction: HapticInstruction)
}

@MainActor
final class ImpactHapticService: HapticService {
    private let generator = UIImpactFeedbackGenerator(style: .heavy)

    init() {
        generator.prepare()
    }

    func play(_ instruction: HapticInstruction) {
        generator.impactOccurred(intensity: CGFloat(instruction.intensity.clampedToUnitInterval))
        generator.prepare()
    }
}
