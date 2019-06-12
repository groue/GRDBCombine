import UIKit
import SwiftUI

class MenuViewController: UITableViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = true
    }
    
    @objc override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.row {
        case 0:
            performSegue(withIdentifier: "count", sender: self)
        case 1:
            performSegue(withIdentifier: "hallOfFame", sender: self)
        case 2:
            let view = HallOfFameView(viewModel: HallOfFameViewModel())
            let viewController = UIHostingController(rootView: view)
            show(viewController, sender: self)
        default:
            break
        }
    }
}
