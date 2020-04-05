import Foundation
import GRDB

struct AppDatabase {
	static var shared = AppDatabase.loadSharedDatabase()
	
	static func loadSharedDatabase() -> AppDatabase {
		do {
			let databaseURL = try FileManager.default
				.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
				.appendingPathComponent("db.sqlite")
			
			return try self.init(withDatabasePath: databaseURL.path)
		}
		catch {
			fatalError("Couldn't load main application database")
		}
	}
	
	
	let db: DatabasePool
	
	init(withDatabasePath path: String) throws {
        // Connect to the database
        // See https://github.com/groue/GRDB.swift/blob/master/README.md#database-connections
        self.db = try DatabasePool(path: path)
        
        // Define the database schema
		try migrator.migrate(self.db)
    }
    
    /// The DatabaseMigrator that defines the database schema.
    ///
    /// See https://github.com/groue/GRDB.swift/blob/master/README.md#migrations
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("createPlayer") { db in
            // Create a table
            // See https://github.com/groue/GRDB.swift#create-tables
            try db.create(table: "player") { t in
                t.autoIncrementedPrimaryKey("id")
                
                // Sort player names in a localized case insensitive fashion by default
                // See https://github.com/groue/GRDB.swift/blob/master/README.md#unicode
                t.column("name", .text).notNull().collate(.localizedCaseInsensitiveCompare)
                
                t.column("score", .integer).notNull()
            }
        }
        
        migrator.registerMigration("fixtures") { db in
            // Populate the players table with random data
            for _ in 0..<8 {
                var player = Player(id: nil, name: Player.randomName(), score: Player.randomScore())
                try player.insert(db)
            }
        }
        
//        // Migrations for future application versions will be inserted here:
//        migrator.registerMigration(...) { db in
//            ...
//        }
        
        return migrator
    }
}
