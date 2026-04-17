import Foundation

struct WordVisualStyle: Equatable {
    let opacity: Double
}

protocol VisualMappingService {
    func style(forDistanceFromCurrent distanceFromCurrent: Int) -> WordVisualStyle
}

struct PlaybackTrailOpacityVisualMapper: VisualMappingService {
    let minimumOpacity: Double
    let decayFactor: Double

    init(minimumOpacity: Double = 0.24, decayFactor: Double = 0.78) {
        self.minimumOpacity = minimumOpacity
        self.decayFactor = decayFactor
    }

    func style(forDistanceFromCurrent distanceFromCurrent: Int) -> WordVisualStyle {
        let sanitizedDistance = max(distanceFromCurrent, 0)
        let opacity = max(minimumOpacity, pow(decayFactor, Double(sanitizedDistance)))
        return WordVisualStyle(opacity: opacity)
    }
}
