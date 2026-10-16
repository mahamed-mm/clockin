import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// What a week's postcard says: its dates, its total, its pills and its
/// three biggest subjects. Facts only; names only when asked for. Pure, so
/// it can be tested.
struct PostcardFacts: Equatable, Identifiable {
    struct Subject: Equatable {
        var name: String
        var symbol: String
        var seconds: TimeInterval
    }

    var week: DateInterval
    /// The week's seven days.
    var days: [DayTotal]
    var totalSeconds: TimeInterval
    var sessions: Int
    /// The three biggest, by time.
    var subjects: [Subject]
    /// The week is over, rather than this one so far.
    var isFinished: Bool

    init(week: DateInterval, days: [DayTotal], sessions: [SubjectTotals.Session], today: Date,
         symbol: (String) -> String) {
        self.week = week
        self.days = days
        totalSeconds = sessions.reduce(0) { $0 + $1.seconds }
        self.sessions = sessions.count
        subjects = SubjectTotals(sessions, limit: 3).top.map {
            Subject(name: $0.name, symbol: symbol($0.name), seconds: $0.seconds)
        }
        isFinished = week.end <= today
    }

    var isEmpty: Bool { sessions == 0 }
    var id: Date { week.start }

    /// Tick on the card: feet up with the mug once the week's work is put
    /// down, ready while it's still going. Never a jump or a streak: there's
    /// nothing to win.
    var pose: TickPose { isFinished ? .onBreak : .ready }

    /// "12–18 October 2026", in the phone's language.
    func dates(calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        let lastDay = week.end.addingTimeInterval(-1)
        var style = Date.IntervalFormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                             timeZone: calendar.timeZone)
        style = style.day().month(.wide).year()
        return (week.start..<lastDay).formatted(style)
    }

    /// What the picture shows, for VoiceOver and the image's own description.
    func description(showsNames: Bool, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        let summary = Copy.postcardSummary(dates: dates(calendar: calendar, locale: locale),
                                           seconds: totalSeconds, sessions: sessions)
        guard showsNames, !subjects.isEmpty else { return summary }
        let names = subjects.map { Copy.displayName($0.name) }.formatted(.list(type: .and).locale(locale))
        return summary + " " + Copy.postcardSubjects(names)
    }
}

/// A week as a postcard to share: always light paper with its grain,
/// Fraunces, a small Clockin mark and the dates, Tick, the total, the
/// week's pills and the biggest subjects. A fixed 360 × 450 pt, drawn at
/// 3× into 1080 × 1350, the same on every phone.
struct WeekPostcard: View {
    static let size = CGSize(width: 360, height: 450)

    let facts: PostcardFacts
    let showsNames: Bool
    let today: Date
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                TickFigure(pose: .ready, palette: .standard, detail: .glyph(mouth: true))
                    .frame(width: 22, height: 22)
                Text(verbatim: "Clockin")
                    .font(.retroFixed(.title, size: 17))
                    .foregroundStyle(Retro.ink)
                Spacer(minLength: 8)
                Text(facts.dates(calendar: calendar))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Retro.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Copy.aWeekOfFocus)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(2)
                        .foregroundStyle(Retro.orangeText)
                    DurationText(seconds: facts.totalSeconds, size: 46)
                        .foregroundStyle(Retro.ink)
                    Text(Copy.sessions(facts.sessions))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Retro.inkSoft)
                }
                Spacer(minLength: 0)
                TickFigure(pose: facts.pose, palette: .standard, detail: .handmade)
                    .frame(width: 118, height: 118)
            }
            WeekStrip(totals: facts.days, today: today, calendar: calendar, still: true)
            Rectangle().fill(Retro.ink.opacity(0.12)).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(facts.subjects.enumerated()), id: \.offset) { _, subject in
                    HStack(spacing: 10) {
                        Image(systemName: subject.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Retro.inkSoft)
                            .frame(width: 24)
                        if showsNames {
                            Text(Copy.displayName(subject.name))
                                .font(.retroFixed(.text, size: 17))
                                .foregroundStyle(Retro.ink)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(TimeFormat.duration(subject.seconds))
                            .font(.retroFixed(.text, size: 17))
                            .foregroundStyle(Retro.orangeText)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(PaperBackground().paperGrain())
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(facts.description(showsNames: showsNames, calendar: calendar))
    }
}

/// Draws a postcard and writes it out as a PNG that says what it shows.
@MainActor
enum PostcardRenderer {
    static let scale: CGFloat = 3

    static func image(_ facts: PostcardFacts, showsNames: Bool, today: Date, calendar: Calendar) -> CGImage? {
        let renderer = ImageRenderer(content: WeekPostcard(facts: facts, showsNames: showsNames, today: today,
                                                           calendar: calendar))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(WeekPostcard.size)
        renderer.isOpaque = true
        return renderer.cgImage
    }

    /// The image as a PNG, with `description` as its PNG description and
    /// IPTC caption, so apps that read them can say what's in it.
    nonisolated static func png(_ image: CGImage, description: String) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: description],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCaptionAbstract: description],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// The postcard as a file to share: "Clockin week 42.png".
struct PostcardImage: Transferable {
    var png: Data
    var fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { postcard in
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: postcard.fileName)
            try postcard.png.write(to: url)
            return SentTransferredFile(url)
        }
    }
}
