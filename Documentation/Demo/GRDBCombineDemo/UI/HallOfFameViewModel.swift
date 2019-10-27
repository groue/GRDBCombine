import Combine
import GRDBCombine

class HallOfFameViewModel {
    @Published private var hallOfFame = Players.HallOfFame.empty
    private var cancellables: [AnyCancellable] = []
    
    init() {
        Current.players()
            .hallOfFamePublisher(maxPlayerCount: 10)
            // Perform a synchronous initial fetch
            .fetchOnSubscription()
            // Ignore database errors
            .catch { _ in Empty() }
            .sink { [unowned self] in self.hallOfFame = $0 }
            .store(in: &cancellables)
    }
    
    private static func title(playerCount: Int) -> String {
        "Best of \(playerCount) players"
    }
}

// MARK: - UIViewController support

extension HallOfFameViewModel {
    /// A publisher for the title of the Hall of Fame
    var titlePublisher: AnyPublisher<String, Never> {
        $hallOfFame
            .map { Self.title(playerCount: $0.playerCount) }
            .eraseToAnyPublisher()
    }
    
    /// A publisher for the best players
    var bestPlayersPublisher: AnyPublisher<[Player], Never> {
        $hallOfFame
            .map { $0.bestPlayers }
            .eraseToAnyPublisher()
    }
}

// MARK: - SwiftUI Support

extension HallOfFameViewModel: ObservableObject {
    /// The title of the Hall of Fame
    var title: String {
        Self.title(playerCount: hallOfFame.playerCount)
    }
    
    /// The best players
    var bestPlayers: [Player] {
        hallOfFame.bestPlayers
    }
}
