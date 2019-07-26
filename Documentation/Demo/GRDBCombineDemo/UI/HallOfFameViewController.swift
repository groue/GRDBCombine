import Combine
import UIKit

class HallOfFameViewController: UITableViewController {
    var viewModel = HallOfFameViewModel()
    private var bestPlayersCancellable: AnyCancellable?
    private var navigationItemCancellable: AnyCancellable?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        toolbarItems = playerEditionToolbarItems
        
        // Reload table view whenever the players change.
        bestPlayersCancellable = AnyCancellable(viewModel
            .bestPlayersPublisher
            .sink { [unowned self] _ in self.tableView.reloadData() })
        
        // Update navigationItem title
        navigationItemCancellable = viewModel
            .titlePublisher
            .assign(to: \.title, on: navigationItem)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = false
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.bestPlayers.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "player", for: indexPath)
        let player = viewModel.bestPlayers[indexPath.row]
        cell.textLabel?.text = player.name
        cell.detailTextLabel?.text = "\(player.score)"
        cell.selectionStyle = .none
        return cell
    }
}
