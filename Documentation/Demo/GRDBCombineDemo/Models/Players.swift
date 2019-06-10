import Combine
import Dispatch

/// A type that provides operations on the Player database
enum Players {
    // MARK: - Modify Players
    
    static func deletePlayers() {
        try! Current.database().write { db in
            _ = try Player.deleteAll(db)
        }
    }
    
    static func refreshPlayers() {
        try! Current.database().write { db in
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
                refreshPlayers()
            }
        }
    }
    
    // MARK: - Hall of Fame
    
    struct HallOfFame {
        /// Total number of players
        var playerCount: Int
        
        /// The best ones
        var bestPlayers: [Player]
    }

    func hallOfFamePublisher(maxPlayerCount: Int) -> AnyPublisher<Players.HallOfFame, Error> {
        let count = Player.count(in: Current.database())
        let bestPlayers = Player.limit(maxPlayerCount).orderedByScore().all(in: Current.database())
        // TODO: reader must be shared
        return count
            .combineLatest(bestPlayers) { HallOfFame(playerCount: $0, bestPlayers: $1) }
            .eraseToAnyPublisher()
    }
}
