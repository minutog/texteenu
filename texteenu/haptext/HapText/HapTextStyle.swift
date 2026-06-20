import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {
    static let hapBlue = Color(red: 0.0, green: 0.592, blue: 1.0)
    static let hapBubbleBlue = Color(red: 0.0, green: 0.471, blue: 1.0)
    static let hapGrayBubble = Color(red: 0.902, green: 0.902, blue: 0.922)
    static let hapPlaceholder = Color(red: 0.769, green: 0.769, blue: 0.78)
    static let hapDate = Color(red: 0.541, green: 0.541, blue: 0.557)
    static let hapOptionFill = Color(red: 0.663, green: 0.71, blue: 0.741).opacity(0.48)
    static let hapShadow = Color.black.opacity(0.16)
}

struct FigmaPhoneFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            #if os(iOS)
            let stableViewportHeight = max(proxy.size.height, UIScreen.main.bounds.height)
            let scale = min(proxy.size.width / 402, stableViewportHeight / 874)
            let contentAlignment: Alignment = .top
            let scaleAnchor: UnitPoint = .top
            #else
            let scale = min(proxy.size.width / 402, proxy.size.height / 874)
            let stableViewportHeight = proxy.size.height
            let contentAlignment: Alignment = .center
            let scaleAnchor: UnitPoint = .center
            #endif

            ZStack(alignment: contentAlignment) {
                Color.white

                content
                    .frame(width: 402, height: 874)
                    .background(Color.white)
                    .scaleEffect(scale, anchor: scaleAnchor)
            }
            .frame(width: proxy.size.width, height: stableViewportHeight, alignment: contentAlignment)
            .background(Color.white)
            #if os(iOS)
            .ignoresSafeArea(.keyboard, edges: .all)
            #endif
        }
    }
}

struct ProfileAvatarView: View {
    var user: ChatEndpoint = .gonzalo
    var size: CGFloat = 60

    var body: some View {
        BundlePNGImage(name: user.avatarImageName)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

struct FigmaIconImage: View {
    let name: String
    var color: Color
    var size: CGFloat

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }
}

struct AssetIcon: View {
    let name: String
    var size: CGFloat

    var body: some View {
        BundlePNGImage(name: name)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct TintedAssetIcon: View {
    let name: String
    var color: Color
    var size: CGFloat

    var body: some View {
        #if os(iOS)
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let image = UIImage(contentsOfFile: path)?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .foregroundStyle(color)
                .frame(width: size, height: size)
        } else {
            Color.red
                .frame(width: size, height: size)
        }
        #elseif os(macOS)
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image.templateCopy)
                .resizable()
                .scaledToFit()
                .foregroundStyle(color)
                .frame(width: size, height: size)
        } else {
            Color.red
                .frame(width: size, height: size)
        }
        #else
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: size, height: size)
        #endif
    }
}

struct BundlePNGImage: View {
    let name: String

    var body: some View {
        #if os(iOS)
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .renderingMode(.original)
                .resizable()
        } else {
            Color.red
        }
        #elseif os(macOS)
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .renderingMode(.original)
                .resizable()
        } else {
            Color.red
        }
        #else
        Image(name)
            .renderingMode(.original)
            .resizable()
        #endif
    }
}

#if os(macOS)
private extension NSImage {
    var templateCopy: NSImage {
        let copy = self.copy() as? NSImage ?? self
        copy.isTemplate = true
        return copy
    }
}
#endif

struct WaveformView: View {
    let samples: [Double]
    let color: Color
    var cornerRadius: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let values = samples.isEmpty ? AudioWaveformExtractor.silentSamples(count: 34) : samples
            let barWidth = max(1.25, (proxy.size.width - spacing * CGFloat(max(values.count - 1, 0))) / CGFloat(max(values.count, 1)))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, sample in
                    Capsule()
                        .fill(color)
                        .frame(
                            width: barWidth,
                            height: max(3, proxy.size.height * min(max(sample, 0.08), 1.0))
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
