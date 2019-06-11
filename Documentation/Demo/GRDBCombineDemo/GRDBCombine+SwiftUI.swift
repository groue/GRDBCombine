import Combine
import GRDBCombine
import SwiftUI

extension DatabasePublished: BindableObject {
    
    // 🤯
    public var didChange: AnyPublisher<Int, Never> {
        var count = 0
        return self
            .flatMap { _ -> Publishers.Once<Int, Failure> in
                count += 1
                return Publishers.Once<Int, Failure>(count)
            }
            .catch { _ -> Publishers.Just<Int> in
                count += 1
                return Publishers.Just(count)
            }
            .eraseToAnyPublisher()
    }
}
