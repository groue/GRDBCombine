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
        private struct Context {
            let reader: DatabaseReader
            var queue: DispatchQueue
            var startObservation: StartObservationFunction<Downstream.Input>
            var downstream: Downstream
        }
        
        private enum State {
            /// Waiting for demand, not observing the database.
            ///
            /// If sync is true, then database observation will start
            /// synchronously.
            case waitingForDemand(context: Context, sync: Bool)
            
            /// Observing the database. Self.observer is not nil.
            ///
            /// Demand is the remaining demand.
            ///
            /// If sync is true, then the next database event (value or
            /// completion) will be assumed to be emitted on self.queue, and
            /// handled synchronously. If sync is false, the event will be
            /// dispatched asynchronously on self.queue.
            case observing(context: Context, demand: Subscribers.Demand, sync: Bool)
            
            /// Completed or cancelled, not observing the database.
            case finished
        }
        
        // Observer is not stored in self.state because the first value may be
        // synchronously emitted when the observation starts, even before the
        // observer has been stored in this property. When this happens, we
        // need a proper state so that the first value is properly handled -
        // even if we have no observer yet.
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
            let context = Context(reader: reader, queue: queue, startObservation: startObservation, downstream: downstream)
            self.state = .waitingForDemand(context: context, sync: sync)
        }
        
        func request(_ demand: Subscribers.Demand) {
            lock.synchronized {
                switch state {
                case let .waitingForDemand(context, sync):
                    guard demand > 0 else {
                        return
                    }
                    self.state = .observing(context: context, demand: demand, sync: sync)
                    observer = context.startObservation(
                        sync,
                        context.reader,
                        context.queue,
                        { [weak self] error in self?.receiveCompletion(.failure(error)) },
                        { [weak self] value in self?.receive(value) })
                    
                case let .observing(context: context, demand: currentDemand, sync: sync):
                    state = .observing(context: context, demand: currentDemand + demand, sync: sync)
                    
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
                guard case let .observing(context: context, demand: _, sync: sync) = state else {
                    return
                }
                
                if sync {
                    receiveSync(value)
                } else {
                    context.queue.async {
                        self.receiveSync(value)
                    }
                }
            }
        }
        
        private func receiveSync(_ value: Downstream.Input) {
            lock.synchronized {
                guard case let .observing(context: context, demand: _, sync: _) = state else {
                    return
                }
                
                dispatchPrecondition(condition: .onQueue(context.queue))
                let additionalDemand = context.downstream.receive(value)
                
                if case let .observing(context: context, demand: demand, sync: _) = state {
                    let newDemand = demand + additionalDemand - 1
                    if newDemand == .none {
                        observer = nil
                        // Next demand will start the observation asynchronously
                        state = .waitingForDemand(context: context, sync: false)
                    } else {
                        // Next value will be dispatched asynchronously
                        state = .observing(context: context, demand: newDemand, sync: false)
                    }
                }
            }
        }
        
        private func receiveCompletion(_ completion: Subscribers.Completion<Error>) {
            lock.synchronized {
                guard case let .observing(context: context, demand: _, sync: sync) = state else {
                    return
                }
                
                if sync {
                    receiveCompletionSync(completion)
                } else {
                    context.queue.async {
                        self.receiveCompletionSync(completion)
                    }
                }
            }
        }
        
        private func receiveCompletionSync(_ completion: Subscribers.Completion<Error>) {
            lock.synchronized {
                guard case let .observing(context: context, demand: _, sync: _) = state else {
                    return
                }
                
                dispatchPrecondition(condition: .onQueue(context.queue))
                observer = nil
                state = .finished
                context.downstream.receive(completion: completion)
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
