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
    /// main queue. You can change this behavior by calling the `scheduling(_:)`
    /// method on the returned publisher.
    ///
    /// For example, `scheduling(.immediate)` notifies all values on the main
    /// queue as well, and the first one is immediately notified when the
    /// publisher is subscribed:
    ///
    ///     let cancellable = observation
    ///         .publisher(in: dbQueue)
    ///         .scheduling(.immediate) // <-
    ///         .sink(
    ///             receiveCompletion: { completion in ... },
    ///             receiveValue: { players: [Player] in
    ///                 print("fresh players: \(players)")
    ///             })
    ///     // <- here "fresh players" is already printed.
    ///
    /// - parameter reader: A DatabaseReader.
    /// - returns: A Combine publisher
    public func publisher(in reader: DatabaseReader) -> DatabasePublishers.Value<Reducer.Value> {
        return DatabasePublishers.Value(self, in: reader)
    }
}

extension DatabasePublishers {
    typealias Start<T> = (
        _ scheduler: ValueObservationScheduler,
        _ onError: @escaping (Error) -> Void,
        _ onChange: @escaping (T) -> Void) -> DatabaseCancellable
    
    /// A publisher that tracks changes in the database.
    ///
    /// See `ValueObservation.publisher(in:)`.
    public struct Value<Output>: Publisher {
        
        public typealias Failure = Error
        private let start: Start<Output>
        private var scheduler = ValueObservationScheduler.async(onQueue: .main)
        
        init<Reducer>(
            _ observation: ValueObservation<Reducer>,
            in reader: DatabaseReader)
            where Reducer.Value == Output
        {
            start = { [weak reader] (scheduler, onError, onChange) in
                guard let reader = reader else {
                    return AnyDatabaseCancellable(cancel: { })
                }
                return observation.start(in: reader, scheduling: scheduler, onError: onError, onChange: onChange)
            }
        }
        
        /// Returns a publisher which starts the observation with the given
        /// ValueObservation scheduler.
        ///
        /// For example, `scheduling(.immediate)` notifies all values on the
        /// main queue, and the first one is immediately notified when the
        /// publisher is subscribed:
        ///
        ///     let cancellable = observation
        ///         .publisher(in: dbQueue)
        ///         .scheduling(.immediate) // <-
        ///         .sink(
        ///             receiveCompletion: { completion in ... },
        ///             receiveValue: { players: [Player] in
        ///                 print("fresh players: \(players)")
        ///             })
        ///     // <- here "fresh players" is already printed.
        public func scheduling(_ scheduler: ValueObservationScheduler) -> Self {
            var publisher = self
            publisher.scheduler = scheduler
            return publisher
        }
        
        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
            let subscription = ValueSubscription(
                start: start,
                scheduling: scheduler,
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
            let scheduler: ValueObservationScheduler
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
            scheduling scheduler: ValueObservationScheduler,
            downstream: Downstream)
        {
            state = .waitingForDemand(WaitingForDemand(
                downstream: downstream,
                start: start,
                scheduler: scheduler))
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
                        info.scheduler,
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
