import Combine
import GRDBCombine

/// A view controller that uses a @DatabasePublished property wrapper
class HallOfFameViewModel {
    /// @DatabasePublished automatically updates the hallOfFame
    /// property whenever the database changes.
    ///
    /// The property is a Result because database access may
    /// eventually fail.
    @DatabasePublished(HallOfFame.current, in: Current.database())
    private var hallOfFame: Result<HallOfFame, Error>
    
    /// A publisher for the title of the Hall of Fame
    var titlePublisher: AnyPublisher<String, Never> {
        return $hallOfFame
            .playerCount // AnyPublisher<Int, Error>
            .map { "Best of \($0) players" }
            .replaceError(with: "An error occured")
            .eraseToAnyPublisher()
    }
    
    /// A publisher for the best players
    var bestPlayersPublisher: AnyPublisher<[Player], Never> {
        return $hallOfFame
            .bestPlayers // AnyPublisher<[Player], Error>
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }
    
    /// The current best players
    var bestPlayers: [Player] {
        (try? hallOfFame.get().bestPlayers) ?? []
    }
}
