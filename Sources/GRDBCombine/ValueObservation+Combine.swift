import Combine
import Foundation
import GRDB

/// Combine extensions on [ValueObservation](https://github.com/groue/GRDB.swift/blob/master/README.md#valueobservation).
extension ValueObservation {
    /// Creates a publisher which tracks changes in database values.
    ///
    /// For example:
    ///
    ///     let observation = ValueObservation.tracking { db in
    ///         try Player.fetchAll(db)
    ///     }
    ///     let cancellable = observation
    ///         .publisher(in: dbQueue)
    ///         .sink(
    ///             receiveCompletion: { completion in ... },
    ///             receiveValue: { players: [Player] in
    ///                 print("fresh players: \(players)")
    ///             })
    ///
    /// By default, fresh values are dispatched asynchronously on the
    /// main queue. You can change this behavior by by providing a scheduler.
    ///
    /// For example, `.immediate` notifies all values on the main queue as well,
    /// and the first one is immediately notified when the publisher
    /// is subscribed:
    ///
    ///     let cancellable = observation
    ///         .publisher(
    ///             in: dbQueue,
    ///             scheduling: .immediate) // <-
    ///         .sink(
    ///             receiveCompletion: { completion in ... },
    ///             receiveValue: { players: [Player] in
    ///                 print("fresh players: \(players)")
    ///             })
    ///     // <- here "fresh players" is already printed.
    ///
    /// Note that the `.immediate` scheduler requires that the publisher is
    /// subscribed from the main thread. It raises a fatal error otherwise.
    ///
    /// - parameter reader: A DatabaseReader.
    /// - parameter scheduler: A Scheduler. By default, fresh values are
    ///   dispatched asynchronously on the main queue.
    /// - returns: A Combine publisher
    public func publisher(
        in reader: DatabaseReader,
        scheduling scheduler: ValueObservationScheduler = .async(onQueue: .main))
        -> DatabasePublishers.Value<Reducer.Value>
    {
        return DatabasePublishers.Value(self, in: reader, scheduling: scheduler)
    }
}

extension DatabasePublishers {
    typealias Start<T> = (
        _ onError: @escaping (Error) -> Void,
        _ onChange: @escaping (T) -> Void) -> DatabaseCancellable
    
    /// A publisher that tracks changes in the database.
    ///
    /// See `ValueObservation.publisher(in:scheduling:)`.
    public struct Value<Output>: Publisher {
        public typealias Failure = Error
        private let start: Start<Output>
        
        init<Reducer>(
            _ observation: ValueObservation<Reducer>,
            in reader: DatabaseReader,
            scheduling scheduler: ValueObservationScheduler)
            where Reducer.Value == Output
        {
            start = { [weak reader] (onError, onChange) in
                guard let reader = reader else {
                    return AnyDatabaseCancellable(cancel: { })
                }
                return observation.start(
                    in: reader,
                    scheduling: scheduler,
                    onError: onError,
                    onChange: onChange)
            }
        }
        
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
        // .observing state *before* the observation starts, so that the user
        // can change the state even before the cancellable is known.
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
                    let cancellable = info.start(
                        { [weak self] error in self?.receiveCompletion(.failure(error)) },
                        { [weak self] value in self?.receive(value) })
                    
                    // State may have been altered (error or cancellation)
                    switch state {
                    case .waitingForDemand:
                        preconditionFailure()
                    case .observing:
                        self.cancellable = cancellable
                    case .finished:
                        cancellable.cancel()
                    }
                    
                case var .observing(info):
                    info.remainingDemand += demand
                    state = .observing(info)
                    
                case .finished:
                    break
                }
            }
        }
        
        func cancel() {
            lock.synchronizedWithSideEffect {
                let cancellable = self.cancellable
                self.cancellable = nil
                self.state = .finished
                return {
                    cancellable?.cancel()
                }
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
            lock.synchronizedWithSideEffect {
                if case let .observing(info) = state {
                    cancellable = nil
                    state = .finished
                    return {
                        info.downstream.receive(completion: completion)
                    }
                } else {
                    return noSideEffect
                }
            }
        }
    }
}
