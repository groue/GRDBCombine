import Combine
import Foundation
import GRDB

/// Combine extensions on [ValueObservation](https://github.com/groue/GRDB.swift/blob/master/README.md#valueobservation).
extension ValueObservation where Reducer: ValueReducer {
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
    public func publisher(in reader: DatabaseReader) -> DatabasePublishers.Value<Reducer.Value> {
        return DatabasePublishers.Value(self, in: reader)
    }
}

extension DatabasePublishers {
    /// A helper type which helps erasing the ValueObservation type
    private typealias StartObservationFunction<Output> = (
        _ sync: Bool,
        _ reader: DatabaseReader,
        _ queue: DispatchQueue,
        _ onError: @escaping (Error) -> Void,
        _ onChange: @escaping (Output) -> Void)
        -> TransactionObserver
    
    /// A publisher that tracks changes in the database.
    ///
    /// See `ValueObservation.publisher(in:)`.
    public struct Value<Output>: Publisher {
        public typealias Failure = Error
        private let reader: DatabaseReader
        private var sync: Bool
        private var startObservation: StartObservationFunction<Output>
        
        init<Reducer>(_ observation: ValueObservation<Reducer>, in reader: DatabaseReader)
            where Reducer: ValueReducer, Reducer.Value == Output
        {
            self.reader = reader
            self.startObservation = observation.start(sync:in:queue:onError:onChange:)
            self.sync = false
        }
        
        /// Returns a new publisher which synchronously fetches its initial
        /// value on subscription. Subscription must happen from the main queue,
        /// or you will get a fatal error.
        public func fetchOnSubscription() -> Self {
            var publisher = self
            publisher.sync = true
            return publisher
        }
        
        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
            let subscription = ValueSubscription(
                sync: sync,
                reader: reader,
                queue: DispatchQueue.main, // TODO: allow more scheduling options
                startObservation: startObservation,
                downstream: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }
    
    private class ValueSubscription<Downstream: Subscriber>: Subscription
        where Downstream.Failure == Error
    {
        /// If sync is true, then database observation will start
        /// synchronously.
        private struct WaitingForDemand {
            let downstream: Downstream
            let reader: DatabaseReader
            let queue: DispatchQueue
            let startObservation: StartObservationFunction<Downstream.Input>
            let sync: Bool
        }
        
        /// If sync is true, then the next database event (value or
        /// completion) will be assumed to be emitted on self.queue, and
        /// handled synchronously. If sync is false, the event will be
        /// dispatched asynchronously on self.queue.
        private struct Observing {
            let downstream: Downstream
            let reader: DatabaseReader // Retain writer until subscription is finished
            let queue: DispatchQueue
            var remainingDemand: Subscribers.Demand
            var sync: Bool
        }
        
        private enum State {
            /// Waiting for demand, not observing the database.
            case waitingForDemand(WaitingForDemand)
            
            /// Observing the database. Self.observer is not nil.
            case observing(Observing)
            
            /// Completed or cancelled, not observing the database.
            case finished
        }
        
        // Observer is not stored in self.state because we must enter the
        // .observing state *before* the observation starts.
        private var observer: TransactionObserver?
        private var state: State
        private var lock = NSRecursiveLock() // Allow re-entrancy
        
        init(
            sync: Bool,
            reader: DatabaseReader,
            queue: DispatchQueue,
            startObservation: @escaping StartObservationFunction<Downstream.Input>,
            downstream: Downstream)
        {
            state = .waitingForDemand(WaitingForDemand(
                downstream: downstream,
                reader: reader,
                queue: queue,
                startObservation: startObservation,
                sync: sync))
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
                        reader: info.reader,
                        queue: info.queue,
                        remainingDemand: demand,
                        sync: info.sync))
                    observer = info.startObservation(
                        info.sync,
                        info.reader,
                        info.queue,
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
                observer = nil
                state = .finished
            }
        }
        
        private func receive(_ value: Downstream.Input) {
            lock.synchronized {
                if case let .observing(info) = state {
                    if info.sync {
                        receiveSync(value)
                    } else {
                        info.queue.async {
                            self.receiveSync(value)
                        }
                    }
                }
            }
        }
        
        private func receiveCompletion(_ completion: Subscribers.Completion<Error>) {
            lock.synchronized {
                if case let .observing(info) = state {
                    if info.sync {
                        receiveCompletionSync(completion)
                    } else {
                        info.queue.async {
                            self.receiveCompletionSync(completion)
                        }
                    }
                }
            }
        }
        
        private func receiveSync(_ value: Downstream.Input) {
            lock.synchronized {
                if case let .observing(info) = state,
                    info.remainingDemand > .none
                {
                    dispatchPrecondition(condition: .onQueue(info.queue))
                    let additionalDemand = info.downstream.receive(value)
                    if case var .observing(info) = state {
                        info.remainingDemand += additionalDemand
                        info.remainingDemand -= 1
                        // Next value will be dispatched asynchronously
                        info.sync = false
                        state = .observing(info)
                    }
                }
            }
        }
        
        private func receiveCompletionSync(_ completion: Subscribers.Completion<Error>) {
            lock.synchronized {
                if case let .observing(info) = state {
                    dispatchPrecondition(condition: .onQueue(info.queue))
                    observer = nil
                    state = .finished
                    info.downstream.receive(completion: completion)
                }
            }
        }
    }
}

// MARK: - Erase ValueObservation.Reducer

extension ValueObservation where Reducer: ValueReducer {
    /// Support for DatabasePublishers.Value.
    ///
    /// If `sync` is false, starts observation and emits all values
    /// asynchronously on `queue`.
    ///
    /// If `sync` is true, starts observation and emits all values
    /// asynchronously on `queue`, but the first one which is
    /// emitted synchronously.
    fileprivate func start(
        sync: Bool,
        in reader: DatabaseReader,
        queue: DispatchQueue,
        onError: @escaping (Error) -> Void,
        onChange: @escaping (Reducer.Value) -> Void)
        -> TransactionObserver
    {
        var scheduledObservation = self
        if sync {
            // Deal with unsafe GRDB scheduling: we can only
            // guarantee correct ordering of values if observation
            // starts on the same queue as the queue values are
            // dispatched on.
            dispatchPrecondition(condition: .onQueue(queue))
            scheduledObservation.scheduling = .unsafe(startImmediately: true)
        } else {
            scheduledObservation.scheduling = .async(onQueue: queue, startImmediately: true)
        }
        return scheduledObservation.start(in: reader, onError: onError, onChange: onChange)
    }
}
