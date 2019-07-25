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
    /// A publisher that tracks changes in the database.
    ///
    /// See `ValueObservation.publisher(in:)`.
    public struct Value<Output>: Publisher {
        public typealias Failure = Error
        let reader: DatabaseReader
        private var startObservation: StartObservationFunction<Output>
        private let startObservationSync: StartObservationFunction<Output>
        private let startObservationAsync: StartObservationFunction<Output>
        
        init<Reducer>(_ observation: ValueObservation<Reducer>, in reader: DatabaseReader)
            where Reducer: ValueReducer, Reducer.Value == Output
        {
            self.reader = reader
            self.startObservationSync = observation.startSync(in:queue:willSubscribeSync:onError:onChange:)
            self.startObservationAsync = observation.startAsync(in:queue:willSubscribeSync:onError:onChange:)
            
            // Default to async fetch of initial value
            self.startObservation = startObservationAsync
        }
        
        /// Returns a new publisher which synchronously fetches its initial
        /// value on subscription. Subscription must happen from the main queue,
        /// or you will get a fatal error.
        public func fetchOnSubscription() -> Self {
            var publisher = self
            publisher.startObservation = startObservationSync
            return publisher
        }
        
        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
            let subscription = ValueSubscription<Output>(
                startObservation: startObservation,
                reader: reader,
                queue: DispatchQueue.main, // TODO: allow more scheduling options
                receiveCompletion: subscriber.receive(completion:),
                receive: subscriber.receive(_:))
            subscriber.receive(subscription: subscription)
        }
    }
    
    private class ValueSubscription<Output>: Subscription {
        private enum State {
            // Waiting for demand, not observing the database.
            case waitingForDemand
            
            // Observing the database. Self.observer is not nil.
            //
            // Demand is the remaining demand.
            //
            // If sync is true, then the next database event (value or
            // completion) will be assumed to be emitted on self.queue, and
            // handled synchronously. If sync is false, the event will be
            // dispatched asynchronously on self.queue.
            //
            // Sync may be true only once, when the subscription starts.
            case observing(demand: Subscribers.Demand, sync: Bool)
            
            // Completed or cancelled, not observing the database.
            case finished
        }
        private let startObservation: StartObservationFunction<Output>
        private let reader: DatabaseReader
        private let queue: DispatchQueue
        private let _receiveCompletion: (Subscribers.Completion<Error>) -> Void
        private let _receive: (Output) -> Subscribers.Demand
        private var observer: TransactionObserver?
        private var state: State = .waitingForDemand
        private var lock = NSRecursiveLock() // Allow re-entrancy
        
        init(
            startObservation: @escaping StartObservationFunction<Output>,
            reader: DatabaseReader,
            queue: DispatchQueue,
            receiveCompletion: @escaping (Subscribers.Completion<Error>) -> Void,
            receive: @escaping (Output) -> Subscribers.Demand)
        {
            self.startObservation = startObservation
            self.reader = reader
            self.queue = queue
            self._receiveCompletion = receiveCompletion
            self._receive = receive
        }
        
        func request(_ demand: Subscribers.Demand) {
            lock.synchronized {
                
                switch state {
                case .waitingForDemand:
                    guard demand > 0 else {
                        return
                    }
                    observer = startObservation(
                        reader,
                        queue,
                        { sync in self.state = .observing(demand: demand, sync: sync) },
                        { [weak self] error in self?.receiveCompletion(.failure(error)) },
                        { [weak self] value in self?.receive(value) })
                    
                case let .observing(demand: currentDemand, sync: sync):
                    state = .observing(demand: currentDemand + demand, sync: sync)
                    
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
        
        private func receive(_ value: Output) {
            lock.synchronized {
                guard case let .observing(demand: _, sync: sync) = state else {
                    return
                }
                
                if sync {
                    receiveSync(value)
                } else {
                    queue.async {
                        self.receiveSync(value)
                    }
                }
            }
        }
        
        private func receiveSync(_ value: Output) {
            dispatchPrecondition(condition: .onQueue(queue))
            
            lock.synchronized {
                guard case .observing = state else {
                    return
                }
                
                let additionalDemand = _receive(value)
                
                if case let .observing(demand: demand, sync: _) = state {
                    let newDemand = demand + additionalDemand - 1
                    if newDemand == .none {
                        observer = nil
                        state = .waitingForDemand
                    } else {
                        state = .observing(demand: newDemand, sync: false)
                    }
                }
            }
        }
        
        private func receiveCompletion(_ completion: Subscribers.Completion<Error>) {
            lock.synchronized {
                guard case let .observing(demand: _, sync: sync) = state else {
                    return
                }
                
                if sync {
                    receiveCompletionSync(completion)
                } else {
                    queue.async {
                        self.receiveCompletionSync(completion)
                    }
                }
            }
        }
        
        private func receiveCompletionSync(_ completion: Subscribers.Completion<Error>) {
            dispatchPrecondition(condition: .onQueue(queue))
            
            lock.synchronized {
                guard case .observing = state else {
                    return
                }
                
                observer = nil
                state = .finished
                _receiveCompletion(completion)
            }
        }
    }
}

// MARK: - Erase ValueObservation.Reducer

private typealias StartObservationFunction<Output> = (DatabaseReader, DispatchQueue, (Bool) -> Void, @escaping (Error) -> Void, @escaping (Output) -> Void) -> TransactionObserver

extension ValueObservation where Reducer: ValueReducer {
    /// Support for DatabasePublishers.Value.
    ///
    /// Start observation and emit values asynchronously on queue, but the first
    /// one which is emitted synchronously.
    fileprivate func startSync(
        in reader: DatabaseReader,
        queue: DispatchQueue,
        willSubscribeSync: (Bool) -> Void,
        onError: @escaping (Error) -> Void,
        onChange: @escaping (Reducer.Value) -> Void)
        -> TransactionObserver
    {
        willSubscribeSync(true)
        
        // Deal with unsafe GRDB scheduling: we can only
        // guarantee correct ordering of values if observation
        // starts on the same queue as the queue values are
        // dispatched on.
        dispatchPrecondition(condition: .onQueue(queue))
        var observation = self
        observation.scheduling = .unsafe(startImmediately: true)
        return start(in: reader, onError: onError, onChange: onChange)
    }
    
    /// Support for DatabasePublishers.Value.
    ///
    /// Start observation and emit values asynchronously on queue.
    fileprivate func startAsync(
        in reader: DatabaseReader,
        queue: DispatchQueue,
        willSubscribeSync: (Bool) -> Void,
        onError: @escaping (Error) -> Void,
        onChange: @escaping (Reducer.Value) -> Void)
        -> TransactionObserver
    {
        willSubscribeSync(false)
        
        var observation = self
        observation.scheduling = .async(onQueue: queue, startImmediately: true)
        return start(in: reader, onError: onError, onChange: onChange)
    }
}
