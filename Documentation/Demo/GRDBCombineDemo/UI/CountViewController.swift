import Combine
import GRDBCombine
import UIKit

/// A view controller that uses a raw DatabasePublisher
class CountViewController: UIViewController {
    @IBOutlet private weak var countLabel: UILabel!
    private var cancellers = Cancellers()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        toolbarItems = playerEditionToolbarItems
        
        cancellers += Player.count(in: Current.database())
            .map { "\($0)" }
            .catch { _ in Publishers.Just("An error occurred") }
            .assign(to: \.text, on: countLabel)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = false
    }
}
