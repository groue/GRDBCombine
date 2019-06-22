import Combine
import GRDB
import GRDBCombine
import Dispatch

/// A namespace that provides operations on the Player database
enum Players {
    
    // MARK: - Modify Players
    
    static func deletePlayers() throws {
        try Current.database().write { db in
            _ = try Player.deleteAll(db)
        }
    }
    
    static func refreshPlayers() throws {
        try Current.database().write { db in
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
    
    static func stressTest() {
        for _ in 0..<50 {
            DispatchQueue.global().async {
                try? refreshPlayers()
            }
        }
    }
    
    // MARK: - Hall of Fame
    
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
    
    static func hallOfFame(maxPlayerCount: Int) -> DatabasePublishers.Value<HallOfFame> {
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
        
        return hallOfFame.publisher(in: Current.database())
    }
}
