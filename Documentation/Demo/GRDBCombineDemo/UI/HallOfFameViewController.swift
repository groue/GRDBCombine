import Combine
import UIKit

class HallOfFameViewController: UITableViewController {
    var viewModel = HallOfFameViewModel()
    private var players: [Player] = []
    private var needsPlayersAnimation = false
    private var cancellables: [AnyCancellable] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        toolbarItems = playerEditionToolbarItems
        
        viewModel
            .bestPlayersPublisher
            .sink { [unowned self] in self.updatePlayers($0) }
            .store(in: &cancellables)
        
        viewModel
            .titlePublisher
            .assign(to: \.title, on: navigationItem)
            .store(in: &cancellables)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = false
    }
    
    // MARK: - UITableViewDataSource
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        players.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "player", for: indexPath)
        let player = players[indexPath.row]
        cell.textLabel?.text = player.name
        cell.detailTextLabel?.text = "\(player.score)"
        cell.selectionStyle = .none
        return cell
    }
    
    // MARK: - Private
    
    private func updatePlayers(_ players: [Player]) {
        // Don't animate first update
        if !needsPlayersAnimation {
            needsPlayersAnimation = true
            self.players = players
            tableView.reloadData()
            return
        }
        
        // Compute difference between current and new list of players
        let difference = players
            .difference(from: self.players)
            .inferringMoves()
        
        // Apply those changes to the table view
        tableView.performBatchUpdates({
            self.players = players
            for change in difference {
                switch change {
                case let .remove(offset, _, associatedWith):
                    if let associatedWith = associatedWith {
                        self.tableView.moveRow(
                            at: IndexPath(row: offset, section: 0),
                            to: IndexPath(row: associatedWith, section: 0))
                    } else {
                        self.tableView.deleteRows(
                            at: [IndexPath(row: offset, section: 0)],
                            with: .fade)
                    }
                case let .insert(offset, _, associatedWith):
                    if associatedWith == nil {
                        self.tableView.insertRows(
                            at: [IndexPath(row: offset, section: 0)],
                            with: .fade)
                    }
                }
            }
        }, completion: nil)
    }
}
