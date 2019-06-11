import Combine
import Foundation
import GRDB

extension DatabasePublishers {
    /// SubscribeFunction erases the Reducer type of ValueObservation.
    fileprivate typealias SubscribeFunction<Output> = (DatabaseReader, DispatchQueue, (Bool) -> Void, @escaping (Subscribers.Completion<Error>) -> Void, @escaping (Output) -> Void) -> TransactionObserver
    
    /// A publisher that tracks changes in the database.
    ///
    /// It emits all fresh values, and its eventual error completion, on the
    /// main queue.
    ///
    /// By default, DatabasePublishers.Value can be subscribed from any dispatch
    /// queue, and emits its first value asynchronously.
    ///
    /// You can force the puublisher to start synchronously with the
    /// `fetchOnSubscription()` method. Subscription must then happen from the
    /// main queue, or you will get a fatal error.
    public struct Value<Output>: Publisher {
        public typealias Failure = Error
        let reader: DatabaseReader
        var fetchOnRequest: Bool
        private let subscribeSync: SubscribeFunction<Output>
        private let subscribeASync: SubscribeFunction<Output>

        public init<Reducer>(_ observation: ValueObservation<Reducer>, in reader: DatabaseReader)
            where Reducer: ValueReducer, Reducer.Value == Output
        {
            self.reader = reader
            self.fetchOnRequest = false
            self.subscribeSync = observation.subscribeSync(in:queue:willSubscribeSync:receiveCompletion:receive:)
            self.subscribeASync = observation.subscribeSync(in:queue:willSubscribeSync:receiveCompletion:receive:)
        }
        
        /// Returns a new publisher which fetches initial values on
        /// subscription. Subscription must happen from the main queue, or you
        /// will get a fatal error.
        public func fetchOnSubscription() -> Self {
            var publisher = self
            publisher.fetchOnRequest = true
            return publisher
        }
        
        public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
            let subscription = ValueSubscription<Output>(
                subscribe: fetchOnRequest ? subscribeSync : subscribeASync,
                reader: reader,
                queue: DispatchQueue.main,
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
        private let subscribe: SubscribeFunction<Output>
        private let reader: DatabaseReader
        private let queue: DispatchQueue
        private let _receiveCompletion: (Subscribers.Completion<Error>) -> Void
        private let _receive: (Output) -> Subscribers.Demand
        private var observer: TransactionObserver?
        private var state: State = .waitingForDemand
        private var lock = NSRecursiveLock() // Allow re-entrancy
        
        init(
            subscribe: @escaping SubscribeFunction<Output>,
            reader: DatabaseReader,
            queue: DispatchQueue,
            receiveCompletion: @escaping (Subscribers.Completion<Error>) -> Void,
            receive: @escaping (Output) -> Subscribers.Demand
            )
        {
            self.subscribe = subscribe
            self.reader = reader
            self.queue = queue
            self._receiveCompletion = receiveCompletion
            self._receive = receive
        }
        
        func request(_ demand: Subscribers.Demand) {
            lock.lock()
            defer { lock.unlock() }
            
            switch state {
            case .waitingForDemand:
                guard demand > 0 else {
                    return
                }
                observer = subscribe(
                    reader,
                    queue,
                    { self.state = .observing(demand: demand, sync: $0) },
                    receiveCompletion,
                    receive)

            case let .observing(demand: currentDemand, sync: sync):
                state = .observing(demand: currentDemand + demand, sync: sync)
            
            case .finished:
                break
            }
        }
        
        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            
            observer = nil
            state = .finished
        }
        
        private func receive(_ value: Output) {
            lock.lock()
            defer { lock.unlock() }
            
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
        
        private func receiveSync(_ value: Output) {
            dispatchPrecondition(condition: .onQueue(queue))
            
            lock.lock()
            defer { lock.unlock() }
            
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
        
        private func receiveCompletion(_ completion: Subscribers.Completion<Error>) {
            lock.lock()
            defer { lock.unlock() }
            
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

        private func receiveCompletionSync(_ completion: Subscribers.Completion<Error>) {
            dispatchPrecondition(condition: .onQueue(queue))
            
            lock.lock()
            defer { lock.unlock() }
            
            guard case .observing = state else {
                return
            }
            
            observer = nil
            state = .finished
            _receiveCompletion(completion)
        }
    }
}

// Erase ValueReducer
extension ValueObservation where Reducer: ValueReducer {
    fileprivate func subscribeSync(
        in reader: DatabaseReader,
        queue: DispatchQueue,
        willSubscribeSync: (Bool) -> Void,
        receiveCompletion: @escaping (Subscribers.Completion<Error>) -> Void,
        receive: @escaping (Reducer.Value) -> Void)
        -> TransactionObserver
    {
        // Deal with unsafe GRDB scheduling: we can only
        // guarantee correct ordering of values if observation
        // starts on the same queue as the queue values are
        // dispatched on.
        dispatchPrecondition(condition: .onQueue(queue))
        var observation = self
        observation.scheduling = .unsafe(startImmediately: true)
        
        willSubscribeSync(true)
        
        return reader.add(
            observation: observation,
            onError: { receiveCompletion(.failure($0)) },
            onChange: receive)
    }

    fileprivate func subscribeAsync(
        in reader: DatabaseReader,
        queue: DispatchQueue,
        willSubscribeSync: (Bool) -> Void,
        receiveCompletion: @escaping (Subscribers.Completion<Error>) -> Void,
        receive: @escaping (Reducer.Value) -> Void)
        -> TransactionObserver
    {
        var observation = self
        observation.scheduling = .async(onQueue: queue, startImmediately: true)
        
        willSubscribeSync(false)
        
        return reader.add(
            observation: observation,
            onError: { receiveCompletion(.failure($0)) },
            onChange: receive)
    }
}
