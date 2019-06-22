import Combine
import GRDBCombine
import UIKit

/// A view controller that uses a raw DatabasePublisher
class CountViewController: UIViewController {
    @IBOutlet private weak var countLabel: UILabel!
    private var countCanceller: AnyCancellable?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        toolbarItems = playerEditionToolbarItems
        
        let countPublisher = Player.observationForCount().publisher(in: Current.database())
        countCanceller = countPublisher
            .map { "\($0)" }
            .replaceError(with: "An error occurred")
            .assign(to: \.text, on: countLabel)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = false
    }
}
