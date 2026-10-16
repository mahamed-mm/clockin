import SwiftUI

/// The week's postcard before it's shared: it settles from a slight tilt,
/// like a card put down on a table; names are off unless switched on. The
/// picture is drawn when the sheet opens or the switch changes, and only
/// leaves the phone if you share it.
struct PostcardPreview: View {
    let facts: PostcardFacts
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsNames = false
    @State private var postcard: PostcardImage?
    @State private var preview: Image?
    @State private var settled = false

    /// The tilt it starts from: none with Reduce Motion or Low Power Mode.
    static func startTilt(reduceMotion: Bool, constrained: Bool) -> Double {
        reduceMotion || constrained ? 0 : -6
    }

    var body: some View {
        let still = Self.startTilt(reduceMotion: reduceMotion, constrained: services.power.isConstrained) == 0
        let description = facts.description(showsNames: showsNames, calendar: services.calendar)
        VStack(spacing: Space.l) {
            ZStack(alignment: .topLeading) {
                Text(Copy.shareThisWeek)
                    .retroFont(.headline)
                    .foregroundStyle(Retro.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 44)
                    .padding(.top, Space.xs)
                    .accessibilityAddTraits(.isHeader)
                CloseButton { dismiss() }
            }
            Group {
                if let preview {
                    preview
                        .resizable()
                        .aspectRatio(WeekPostcard.size, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                } else {
                    Color.clear.aspectRatio(WeekPostcard.size, contentMode: .fit)
                }
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 220 : 300)
            .rotationEffect(.degrees(settled || still ? 0 : Self.startTilt(reduceMotion: false, constrained: false)))
            .scaleEffect(settled || still ? 1 : 0.96)
            .accessibilityElement()
            .accessibilityLabel(description)
            .accessibilityAddTraits(.isImage)
            Toggle(Copy.showNames, isOn: $showsNames)
                .font(.retro(.body))
                .foregroundStyle(Retro.ink)
                .tint(Retro.orange)
            if let postcard {
                ShareLink(item: postcard, preview: SharePreview(Copy.shareThisWeek, image: preview ?? Image(systemName: "photo"))) {
                    Label(Copy.share, systemImage: "square.and.arrow.up")
                        .font(.retro(.button))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.xs)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .tint(Retro.orange)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .task(id: showsNames) { draw(description: description) }
        .onAppear {
            guard !still else { return }
            withAnimation(.spring(response: 0.7 * Motion.speed, dampingFraction: 0.72).delay(0.1)) { settled = true }
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    private func draw(description: String) {
        guard let image = PostcardRenderer.image(facts, showsNames: showsNames, today: services.today,
                                                 calendar: services.calendar) else { return }
        preview = Image(decorative: image, scale: PostcardRenderer.scale)
        let week = services.calendar.component(.weekOfYear, from: facts.week.start)
        postcard = PostcardRenderer.png(image, description: description).map {
            PostcardImage(png: $0, fileName: Copy.postcardFileName(week: week))
        }
    }
}
