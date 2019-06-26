import Combine
import GRDB
import GRDBCombine
import Dispatch

/// Players is responsible for high-level operations on the players database.
struct Players {
    private let database: DatabaseWriter
    
    init(database: DatabaseWriter) {
        self.database = database
    }
    
    // MARK: - Modify Players
    
    func deleteAll() throws {
        try database.write { db in
            _ = try Player.deleteAll(db)
        }
    }
    
    func refresh() throws {
        try database.write { db in
            if try Player.fetchCount(db) == 0 {
                // Insert new random players
                for _ in 0..<8 {
                    var player = Player(id: nil, name: Player.randomName(), score: Player.randomScore())
                    try player.insert(db)
                }
            } else {
                // Insert a player
                if Bool.random() {
                    var player = Player(id: nil, name: Player.randomName(), score: Player.randomScore())
                    try player.insert(db)
                }
                // Delete a random player
                if Bool.random() {
                    try Player.order(sql: "RANDOM()").limit(1).deleteAll(db)
                }
                // Update some players
                for var player in try Player.fetchAll(db) where Bool.random() {
                    player.score = Player.randomScore()
                    try player.update(db)
                }
            }
        }
    }
    
    func stressTest() {
        for _ in 0..<50 {
            DispatchQueue.global().async {
                try? self.refresh()
            }
        }
    }
    
    // MARK: - Access Players
    
    /// A Hole of Fame
    struct HallOfFame {
        /// Total number of players
        var playerCount: Int
        
        /// The best ones
        var bestPlayers: [Player]
        
        init(playerCount: Int, bestPlayers: [Player]) {
            // Safety check
            assert(playerCount >= bestPlayers.count, "inconsistent HallOfFame")
            self.playerCount = playerCount
            self.bestPlayers = bestPlayers
        }
    }
    
    /// A publisher that tracks changes in the Hall of Fame
    func hallOfFamePublisher(maxPlayerCount: Int) -> DatabasePublishers.Value<HallOfFame> {
        let playerCount = Player.observationForCount()
        
        let bestPlayers = Player
            .limit(maxPlayerCount)
            .orderedByScore()
            .observationForAll()
        
        // We combine database observations instead of combining publishers
        // with the combineLatest method. This is because we care about data
        // consistency. See the HallOfFame initializer.
        let hallOfFame = playerCount.combine(bestPlayers) {
            HallOfFame(playerCount: $0, bestPlayers: $1)
        }
        
        return hallOfFame.publisher(in: database)
    }
    
    /// A publisher that tracks changes in the number of players
    func playerCountPublisher() -> DatabasePublishers.Value<Int> {
        Player.observationForCount().publisher(in: database)
    }
}
