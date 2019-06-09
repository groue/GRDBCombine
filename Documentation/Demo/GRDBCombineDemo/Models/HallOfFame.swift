import GRDB
import GRDBCombine

struct HallOfFame {
    var playerCount: Int
    var bestPlayers: [Player]
    
    /// A database observation for the current HallOfFame,
    /// with guarantee of database consistency.
    static var current = ValueObservation
        .combine(
            Player.observeCount,
            Player.limit(10).orderedByScore().observeAll)
        .map { HallOfFame(playerCount: $0, bestPlayers: $1) }
}
