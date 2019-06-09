import Combine
import GRDBCombine
import SwiftUI

/// A view controller that uses a @DatabasePublished property wrapper, and
/// feeds both HallOfFameViewController, and the SwiftUI HallOfFameView.
class HallOfFameViewModel: BindableObject {
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
    
    /// The current title
    var title: String {
        (try? "Best of \(hallOfFame.get().playerCount) players") ?? "An error occured"
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
    
    var didChange: DatabasePublished<HallOfFame> { $hallOfFame }
}
