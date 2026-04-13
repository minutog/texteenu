import Foundation

struct WordVisualStyle: Equatable {
    let opacity: Double
}

protocol VisualMappingService {
    func style(for emotionIntensity: Double) -> WordVisualStyle
}

struct EmotionOpacityVisualMapper: VisualMappingService {
    let minimumOpacity: Double

    init(minimumOpacity: Double = 0.25) {
        self.minimumOpacity = minimumOpacity
    }

    func style(for emotionIntensity: Double) -> WordVisualStyle {
        let clampedEmotion = emotionIntensity.clampedToUnitInterval
        let opacity = minimumOpacity + ((1 - minimumOpacity) * clampedEmotion)
        return WordVisualStyle(opacity: opacity)
    }
}
