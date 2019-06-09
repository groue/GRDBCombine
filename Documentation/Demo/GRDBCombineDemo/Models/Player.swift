import GRDB

// A plain Player struct
struct Player {
    // Use Int64 for auto-incremented database ids
    var id: Int64?
    var name: String
    var score: Int
}

// MARK: - Persistence

// Turn Player into a Codable Record.
// See https://github.com/groue/GRDB.swift/blob/master/README.md#records
extension Player: Codable, FetchableRecord, MutablePersistableRecord {
    // Define database columns from CodingKeys
    fileprivate enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let score = Column(CodingKeys.score)
    }
    
    // Update a player id after it has been inserted in the database.
    mutating func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}

// MARK: - Database access

// Define some useful player requests.
// See https://github.com/groue/GRDB.swift/blob/master/README.md#requests
extension DerivableRequest where RowDecoder == Player {
    func orderedByName() -> Self {
        order(Player.Columns.name)
    }
    
    func orderedByScore() -> Self {
        order(Player.Columns.score.desc, Player.Columns.name)
    }
}

// MARK: - Player Randomization

extension Player {
    private static let names = [
        "Arthur", "Anita", "Barbara", "Bernard", "Clément", "Chiara", "David",
        "Dean", "Éric", "Elena", "Fatima", "Frederik", "Gilbert", "Georgette",
        "Henriette", "Hassan", "Ignacio", "Irene", "Julie", "Jack", "Karl",
        "Kristel", "Louis", "Liz", "Masashi", "Mary", "Noam", "Nolwenn",
        "Ophelie", "Oleg", "Pascal", "Patricia", "Quentin", "Quinn", "Raoul",
        "Rachel", "Stephan", "Susie", "Tristan", "Tatiana", "Ursule", "Urbain",
        "Victor", "Violette", "Wilfried", "Wilhelmina", "Yvon", "Yann",
        "Zazie", "Zoé"]
    
    static func randomName() -> String {
        names.randomElement()!
    }
    
    static func randomScore() -> Int {
        10 * Int.random(in: 0...100)
    }
}
