import Foundation
import GRDB

/// The database everything the user keeps lives in.
///
/// `~/Library/Application Support/Retain/Retain.sqlite`, beside the
/// `Recordings/` folder `RecordingStore` writes into. Retain is not sandboxed,
/// so that is the real path and not a container.
///
/// Opening it always runs the migrator, so a connection handed out by this type
/// is a connection whose schema is current.
nonisolated final class RetainDatabase: Sendable {

    /// The writer every repository goes through.
    ///
    /// Deliberately `any DatabaseWriter` and not a concrete type: the app uses
    /// a `DatabasePool` and the tests an in-memory `DatabaseQueue`, and no
    /// repository has any business knowing which.
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    // MARK: - Opening

    static var url: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Retain", isDirectory: true)
            .appendingPathComponent("Retain.sqlite")
    }

    /// Opens the real database, creating and migrating it if it is not there.
    ///
    /// A `DatabasePool`, not a `DatabaseQueue`. The pass after a lesson writes a
    /// few hundred transcript lines and every note block in one transaction
    /// while the user is reading the library or scrolling a transcript, and a
    /// pool in WAL mode lets those reads run through the write instead of
    /// queueing behind it. A queue would stall the interface for the length of
    /// the slowest write in the app.
    static func openOnDisk() throws -> RetainDatabase {
        let url = Self.url

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let pool = try DatabasePool(path: url.path, configuration: configuration)
            let database = RetainDatabase(writer: pool)
            try database.migrate()
            return database
        } catch {
            // The underlying error is not carried along on purpose: a GRDB or
            // Foundation failure here spells out the file path, and a path
            // under the user's home is content this app does not put into
            // messages, logs or crash reports.
            throw RetainDatabaseError.cannotOpen
        }
    }

    /// A database that exists only for the duration of a test.
    ///
    /// `named` gives two in-memory databases in the same test run separate
    /// storage; two connections opened with the same name share it.
    static func inMemory(named name: String = UUID().uuidString) throws -> RetainDatabase {
        let queue = try DatabaseQueue(named: name, configuration: configuration)
        let database = RetainDatabase(writer: queue)
        try database.migrate()
        return database
    }

    /// The configuration both of them open with.
    static var configuration: Configuration {
        var configuration = Configuration()

        // Foreign keys are what makes deleting a course take its lessons, and
        // its lessons' transcript lines, with it. GRDB enables them by default;
        // it is set here so that stays true if the default ever changes.
        configuration.foreignKeysEnabled = true

        // Never log user content. With this on, GRDB puts statement arguments
        // — which for this app means transcript text and note text — into error
        // descriptions and trace events. It stays off in DEBUG too: a developer
        // reading a lecture transcript out of a console log is exactly the leak
        // this app promises does not happen.
        configuration.publicStatementArguments = false

        return configuration
    }

    // MARK: - Migrations

    func migrate() throws {
        try RetainMigrations.migrator.migrate(writer)
    }

    /// The migrations that have run against this database, in the order they
    /// were applied.
    func appliedMigrations() throws -> [String] {
        try writer.read { try RetainMigrations.migrator.appliedMigrations($0) }
    }
}

// MARK: - Errors

nonisolated enum RetainDatabaseError: Error, Hashable, Sendable {

    /// The database file could not be opened or created.
    case cannotOpen

    /// A migration was asked to roll back that has no rollback path. The
    /// identifier is the migration's; see `RetainMigrations` for why.
    case migrationHasNoRollback(String)

    /// Something was asked to hang off a row that was never written, so there
    /// is no id to hang it off.
    case unsavedRow

    /// A highlight was asked for over a range that is not inside the block it
    /// marks, or that cuts a character in half.
    case invalidHighlightRange

    /// A course was asked to be written into no terms at all. It would be a row
    /// nothing in the interface can reach — every list of courses there is is a
    /// term's list.
    case courseWithoutTerm
}

nonisolated extension RetainDatabaseError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .cannotOpen:
            String(localized: "Retain could not open its library.",
                   comment: "The database file could not be opened or created")
        case .migrationHasNoRollback, .unsavedRow, .invalidHighlightRange, .courseWithoutTerm:
            // None of these is a user-facing state: nothing in the interface
            // rolls a migration back, saves against a row that was never
            // written, marks a range outside the text it is marking, or offers
            // a Create button for a course with no term ticked. Each is a
            // mistake in the caller, and a message about one would mean nothing
            // to the person reading it.
            nil
        }
    }
}
