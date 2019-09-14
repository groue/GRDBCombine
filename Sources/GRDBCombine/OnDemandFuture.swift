import Combine
import Foundation

// TODO: release more memory: some SQLite connections complain that they are
// closed after the database file has been deleted.
/// A publisher that eventually produces one value and then finishes or fails.
///
/// Like a Combine.Future wrapped in Combine.Deferred, OnDemandFuture starts
/// producing its value on demand.
///
/// Unlike Combine.Future wrapped in Combine.Deferred, OnDemandFuture guarantees
/// that it starts producing its value on demand, **synchronously**, and that
/// it produces its value on promise completion, **synchronously**.
///
/// Both two extra scheduling guarantees are used by GRDBCombine in order to be
/// able to spawn concurrent database reads right from the database writer
/// queue, and fulfill GRDB preconditions.
struct OnDemandFuture<Output, Failure : Error>: Publisher {
    typealias Promise = (Result<Output, Failure>) -> Void
    typealias Output = Output
    typealias Failure = Failure
    fileprivate let attemptToFulfill: (@escaping Promise) -> Void
    
    init(_ attemptToFulfill: @escaping (@escaping Promise) -> Void) {
        self.attemptToFulfill = attemptToFulfill
    }
    
    /// :nodoc:
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = DeferredFutureSubscription(
            future: self,
            subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }
}

private class DeferredFutureSubscription<Downstream: Subscriber>: Subscription {
    private enum State {
        case waitingForDemand
        case waitingForFulfillment
        case finished
    }
    
    private let subscriber: Downstream
    private var future: OnDemandFuture<Downstream.Input, Downstream.Failure>?
    private var state: State = .waitingForDemand
    private let lock = NSRecursiveLock() // Allow re-entrancy
    
    init(
        future: OnDemandFuture<Downstream.Input, Downstream.Failure>,
        subscriber: Downstream)
    {
        self.future = future
        self.subscriber = subscriber
    }
    
    func request(_ demand: Subscribers.Demand) {
        lock.synchronized {
            switch state {
            case .waitingForDemand:
                guard demand > 0 else {
                    return
                }
                state = .waitingForFulfillment
                let future = self.future!
                self.future = nil // Release memory
                future.attemptToFulfill { result in
                    switch result {
                    case let .success(value):
                        self.receiveAndComplete(value)
                    case let .failure(error):
                        self.receiveCompletion(.failure(error))
                    }
                }
                
            case .waitingForFulfillment, .finished:
                break
            }
        }
    }
    
    func cancel() {
        lock.synchronized {
            future = nil // Release memory
            state = .finished
        }
    }
    
    private func receiveAndComplete(_ value: Downstream.Input) {
        lock.synchronized {
            guard case .waitingForFulfillment = state else {
                return
            }
            
            state = .finished
            _ = subscriber.receive(value)
            subscriber.receive(completion: .finished)
        }
    }
    
    private func receiveCompletion(_ completion: Subscribers.Completion<Downstream.Failure>) {
        lock.synchronized {
            guard case .waitingForFulfillment = state else {
                return
            }
            
            state = .finished
            subscriber.receive(completion: completion)
        }
    }
}
