import Combine
import UIKit

class HallOfFameViewController: UITableViewController {
    var viewModel = HallOfFameViewModel()
    private var cancellers = Cancellers()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        toolbarItems = Current.playerEditionToolbarItems

        // Reload table view whenever the players change.
        cancellers += viewModel.bestPlayersPublisher.sink { [unowned self] _ in
            self.tableView.reloadData()
        }
        
        // Update navigationItem title (assign won't work?)
        cancellers += viewModel.titlePublisher.sink { [unowned self] in
            self.navigationItem.title = $0
        }
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
        return cell
    }
}
