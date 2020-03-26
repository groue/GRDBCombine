import Combine
import Foundation
import GRDB

/// Combine extensions on [ValueObservation](https://github.com/groue/GRDB.swift/blob/master/README.md#valueobservation).
extension ValueObservation {
    /// Returns a publisher that tracks changes in the database.
    ///
    /// It emits all fresh values, and its eventual error completion, on the
    /// main queue.
    ///
    /// By default, the publisher can be subscribed from any dispatch
    /// queue, and emits a first value asynchronously.
    ///
    /// You can force the publisher to start synchronously with the
    /// `fetchOnSubscription()` method. Subscription must then happen from the
    /// main queue, or you will get a fatal error.
    public func publisher(
        in reader: DatabaseReader,
        scheduler: ValueObservationScheduler = .async(onQueue: .main))
        -> DatabasePublishers.Value<Reducer.Value>
    {
        return DatabasePublishers.Value(self, in: reader, scheduler: scheduler)
    }
}

extension DatabasePublishers {
    typealias Start<T> = (@escaping (Error) -> Void, @escaping (T) -> Void) -> DatabaseCancellable
    
    /// A publisher that tracks changes in the database.
    ///
    /// See `ValueObservation.publisher(in:)`.
    public struct Value<Output>: Publisher {
        
        public typealias Failure = Error
        private let start: Start<Output>
        
        init<Reducer>(
            _ observation: ValueObservation<Reducer>,
            in reader: DatabaseReader,
            scheduler: ValueObservationScheduler)
            where Reducer.Value == Output
        {
            self.start = { [weak reader] (onError, onChange) in
                guard let reader = reader else {
                    return AnyDatabaseCancellable(cancel: { })
                }
                return observation.start(in: reader, scheduler: scheduler, onError: onError, onChange: onChange)
            }
        }
        
        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
            let subscription = ValueSubscription(
                start: start,
                downstream: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }
    
    private class ValueSubscription<Downstream: Subscriber>: Subscription
        where Downstream.Failure == Error
    {
        private struct WaitingForDemand {
            let downstream: Downstream
            let start: Start<Downstream.Input>
        }
        
        private struct Observing {
            let downstream: Downstream
            var remainingDemand: Subscribers.Demand
        }
        
        private enum State {
            /// Waiting for demand, not observing the database.
            case waitingForDemand(WaitingForDemand)
            
            /// Observing the database. Self.observer is not nil.
            case observing(Observing)
            
            /// Completed or cancelled, not observing the database.
            case finished
        }
        
        // Cancellable is not stored in self.state because we must enter the
        // .observing state *before* the observation starts.
        private var cancellable: DatabaseCancellable?
        private var state: State
        private var lock = NSRecursiveLock() // Allow re-entrancy
        
        init(
            start: @escaping Start<Downstream.Input>,
            downstream: Downstream)
        {
            state = .waitingForDemand(WaitingForDemand(
                downstream: downstream,
                start: start))
        }
        
        func request(_ demand: Subscribers.Demand) {
            lock.synchronized {
                switch state {
                case let .waitingForDemand(info):
                    guard demand > 0 else {
                        return
                    }
                    state = .observing(Observing(
                        downstream: info.downstream,
                        remainingDemand: demand))
                    cancellable = info.start(
                        { [weak self] error in self?.receiveCompletion(.failure(error)) },
                        { [weak self] value in self?.receive(value) })
                    
                case var .observing(info):
                    info.remainingDemand += demand
                    state = .observing(info)
                    
                case .finished:
                    break
                }
            }
        }
        
        func cancel() {
            lock.synchronized {
                cancellable?.cancel()
                cancellable = nil
                state = .finished
            }
        }
        
        private func receive(_ value: Downstream.Input) {
            lock.synchronized {
                if case let .observing(info) = state,
                    info.remainingDemand > .none
                {
                    let additionalDemand = info.downstream.receive(value)
                    if case var .observing(info) = state {
                        info.remainingDemand += additionalDemand
                        info.remainingDemand -= 1
                        state = .observing(info)
                    }
                }
            }
        }
        
        private func receiveCompletion(_ completion: Subscribers.Completion<Error>) {
            lock.synchronized {
                if case let .observing(info) = state {
                    cancellable = nil
                    state = .finished
                    info.downstream.receive(completion: completion)
                }
            }
        }
    }
}
