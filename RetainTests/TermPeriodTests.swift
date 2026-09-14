import Foundation
import Testing

@testable import Retain

/// A term's period is never mandatory, so board 05's sidebar subtitle has to
/// read as a sentence with both endpoints, with one, and with none.
///
/// The month labels themselves are formatted against the machine's locale, so
/// nothing here asserts the words "Oct 2025". What is asserted is the shape:
/// which labels appear, whether the dash is there, and that nothing is left
/// dangling — no "– · 4 courses", no separator with nothing in front of it, and
/// no date nobody typed.
@Suite("Term period")
struct TermPeriodTests {

    private let start = StoreFixture.instant(2025, 10)
    private let end = StoreFixture.instant(2026, 3)

    private func term(from startsOn: Date?, to endsOn: Date?) -> Term {
        Term(title: "Third year, winter", startsOn: startsOn, endsOn: endsOn)
    }

    // MARK: - The caption

    @Test("Both endpoints read as a range")
    func bothEndpoints() throws {
        let caption = try #require(TermPeriod.caption(of: term(from: start, to: end)))

        #expect(caption.contains(TermMonth.label(start)))
        #expect(caption.contains(TermMonth.label(end)))
        #expect(caption.contains("–"))
    }

    @Test("A start with no end reads as an open range, not as a dangling dash")
    func startOnly() throws {
        let caption = try #require(TermPeriod.caption(of: term(from: start, to: nil)))

        #expect(caption.contains(TermMonth.label(start)))
        #expect(!caption.contains(TermMonth.label(end)))
        #expect(!caption.contains("–"))
        #expect(!caption.hasSuffix(" "))
    }

    @Test("An end with no start reads the same way round")
    func endOnly() throws {
        let caption = try #require(TermPeriod.caption(of: term(from: nil, to: end)))

        #expect(caption.contains(TermMonth.label(end)))
        #expect(!caption.contains(TermMonth.label(start)))
        #expect(!caption.contains("–"))
    }

    /// Not an empty string and not a placeholder month: a caption that is not
    /// there at all, so the line above it can leave it out.
    @Test("No period at all is no caption at all")
    func noPeriod() {
        #expect(TermPeriod.caption(of: term(from: nil, to: nil)) == nil)
    }

    // MARK: - The sidebar subtitle

    @Test("With a period, the subtitle is the period, the dot and the count")
    func subtitleWithAPeriod() throws {
        let period = try #require(TermPeriod.caption(of: term(from: start, to: end)))
        let subtitle = LibraryCopy.termSubtitle(period: period, courses: LibraryCopy.courses(4))

        #expect(subtitle.hasPrefix(period))
        #expect(subtitle.contains("·"))
        #expect(subtitle.hasSuffix(LibraryCopy.courses(4)))
    }

    @Test("With half a period, the subtitle carries that half and nothing empty")
    func subtitleWithHalfAPeriod() throws {
        let period = try #require(TermPeriod.caption(of: term(from: start, to: nil)))
        let subtitle = LibraryCopy.termSubtitle(period: period, courses: LibraryCopy.courses(4))

        #expect(subtitle.contains(TermMonth.label(start)))
        #expect(!subtitle.contains("–"))
        #expect(subtitle.hasSuffix(LibraryCopy.courses(4)))
    }

    /// The line the whole change is for: a term nobody dated says how many
    /// courses it holds and stops. No leading separator, no empty range.
    @Test("With no period, the subtitle is the count on its own")
    func subtitleWithNoPeriod() {
        let subtitle = LibraryCopy.termSubtitle(period: nil, courses: LibraryCopy.courses(4))

        #expect(subtitle == LibraryCopy.courses(4))
        #expect(!subtitle.contains("·"))
        #expect(!subtitle.contains("–"))
    }

    // MARK: - Through the model

    @Test("The sidebar subtitle of a term with no period is the count alone")
    @MainActor
    func modelSubtitleWithoutAPeriod() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(
            in: database,
            title: "Third year, winter",
            startsOn: nil,
            endsOn: nil,
            isCurrent: true
        )
        try await StoreFixture.course(in: database, term: term, name: "Informatik")

        let model = LibraryModel(database: database)
        await model.load()

        #expect(model.termSubtitle == LibraryCopy.courses(1))
    }

    @Test("The sidebar subtitle of a dated term still carries its period")
    @MainActor
    func modelSubtitleWithAPeriod() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, isCurrent: true)
        try await StoreFixture.course(in: database, term: term, name: "Informatik")

        let model = LibraryModel(database: database)
        await model.load()

        #expect(model.termSubtitle.contains(TermMonth.label(start)))
        #expect(model.termSubtitle.contains(TermMonth.label(end)))
        #expect(model.termSubtitle.hasSuffix(LibraryCopy.courses(1)))
    }

    // MARK: - Round trip

    @Test("A term with no period comes back out of the database with none")
    func noPeriodRoundTrips() async throws {
        let database = try StoreFixture.database()
        let saved = try await StoreFixture.term(in: database, startsOn: nil, endsOn: nil)
        let id = try #require(saved.id)

        let read = try #require(try await LibraryRepository(database).term(id))
        #expect(read.startsOn == nil)
        #expect(read.endsOn == nil)
        #expect(read.title == "Third year, winter")
    }

    @Test("A term with one endpoint comes back with exactly that one")
    func halfAPeriodRoundTrips() async throws {
        let database = try StoreFixture.database()
        let saved = try await StoreFixture.term(in: database, startsOn: start, endsOn: nil)
        let id = try #require(saved.id)

        let read = try #require(try await LibraryRepository(database).term(id))
        #expect(read.startsOn == start)
        #expect(read.endsOn == nil)
    }

    /// A term with no period sorts after the dated ones rather than in the
    /// middle of them, and the picker still opens on whichever is current.
    @Test("An undated term takes its place in the picker without displacing the dated ones")
    func undatedTermsSortLast() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)

        try await StoreFixture.term(in: database, title: "Third year, winter")
        try await StoreFixture.term(
            in: database,
            title: "Third year, summer",
            startsOn: StoreFixture.instant(2026, 4),
            endsOn: StoreFixture.instant(2026, 9)
        )
        try await StoreFixture.term(in: database, title: "Whenever", startsOn: nil, endsOn: nil)

        #expect(try await repository.terms().map(\.title) == [
            "Third year, summer",
            "Third year, winter",
            "Whenever",
        ])
    }
}
