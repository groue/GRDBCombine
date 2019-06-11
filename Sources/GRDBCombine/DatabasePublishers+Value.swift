import Combine
import Foundation
import GRDB

extension DatabasePublishers {
    fileprivate typealias SubscribeFunction<Output> = (DatabaseReader, DispatchQueue, (Bool) -> Void, @escaping (Subscribers.Completion<Error>) -> Void, @escaping (Output) -> Void) throws -> TransactionObserver
    
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
            case waitingForDemand
            case observing(demand: Subscribers.Demand, sync: Bool)
            case completed
            case cancelled
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
                do {
                    observer = try subscribe(reader, queue, { sync in
                        self.state = .observing(demand: demand, sync: true)
                    }, receiveCompletion, receive)
                } catch {
                    receiveCompletion(.failure(error))
                }

            case let .observing(demand: currentDemand, sync: sync):
                state = .observing(demand: currentDemand + demand, sync: sync)
            
            case .completed, .cancelled:
                break
            }
        }
        
        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            
            observer = nil
            state = .cancelled
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
            
            guard case .observing = state else {
                return
            }
            
            observer = nil
            state = .completed
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
        throws -> TransactionObserver
    {
        // Deal with unsafe GRDB scheduling: we can only
        // guarantee correct ordering of values if observation
        // starts on the same queue as the queue values are
        // dispatched on.
        dispatchPrecondition(condition: .onQueue(queue))
        var observation = self
        observation.scheduling = .unsafe(startImmediately: true)
        
        willSubscribeSync(true)
        
        return try reader.add(
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
        throws -> TransactionObserver
    {
        var observation = self
        observation.scheduling = .async(onQueue: queue, startImmediately: true)
        
        willSubscribeSync(false)
        
        return try reader.add(
            observation: observation,
            onError: { receiveCompletion(.failure($0)) },
            onChange: receive)
    }
}
