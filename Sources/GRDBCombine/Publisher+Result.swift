import Combine

extension Publisher {
    /// Returns a publisher of Result
    func eraseToResult() -> AnyPublisher<Result<Output, Failure>, Never> {
        return map { Result<Output, Failure>.success($0) }
            .catch { Just(Result<Output, Failure>.failure($0)) }
            .eraseToAnyPublisher()
    }
}
