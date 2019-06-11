import Combine
import Foundation
import GRDB

extension DatabasePublishers {
    public struct Value<Reducer: ValueReducer>: Publisher {
        public typealias Output = Reducer.Value
        public typealias Failure = Error
        
        let reader: DatabaseReader
        let observation: ValueObservation<Reducer>
        var fetchOnRequest: Bool
        
        public init(_ observation: ValueObservation<Reducer>, in reader: DatabaseReader) {
            self.reader = reader
            self.observation = observation
            self.fetchOnRequest = false
        }
        
        public func fetchOnSubscription() -> Self {
            var publisher = self
            publisher.fetchOnRequest = true
            return publisher
        }
        
        public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
            let subscription = ValueSubscription<Reducer>(
                reader: reader,
                observation: observation,
                queue: DispatchQueue.main,
                fetchOnRequest: fetchOnRequest,
                receiveCompletion: subscriber.receive(completion:),
                receive: subscriber.receive(_:))
            subscriber.receive(subscription: subscription)
        }
    }
    
    private class ValueSubscription<Reducer: ValueReducer>: Subscription {
        private enum State {
            case waitingForDemand
            case observing(demand: Subscribers.Demand, sync: Bool)
            case completed
            case cancelled
        }
        private let reader: DatabaseReader
        private let observation: ValueObservation<Reducer>
        private let queue: DispatchQueue
        private let fetchOnRequest: Bool
        private let _receiveCompletion: (Subscribers.Completion<Error>) -> Void
        private let _receive: (Reducer.Value) -> Subscribers.Demand
        private var observer: TransactionObserver?
        private var state: State = .waitingForDemand
        private var lock = NSRecursiveLock() // Allow re-entrancy
        
        init(
            reader: DatabaseReader,
            observation: ValueObservation<Reducer>,
            queue: DispatchQueue,
            fetchOnRequest: Bool,
            receiveCompletion: @escaping (Subscribers.Completion<Error>) -> Void,
            receive: @escaping (Reducer.Value) -> Subscribers.Demand)
        {
            self.reader = reader
            self.observation = observation
            self.queue = queue
            self.fetchOnRequest = fetchOnRequest
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
                    var observation = self.observation
                    if fetchOnRequest {
                        // Deal with unsafe GRDB scheduling: we can only
                        // guarantee correct ordering of values if observation
                        // starts on the same queue as the queue values are
                        // dispatched on.
                        dispatchPrecondition(condition: .onQueue(queue))
                        state = .observing(demand: demand, sync: true)
                        observation.scheduling = .unsafe(startImmediately: true)
                    } else {
                        state = .observing(demand: demand, sync: false)
                        observation.scheduling = .async(onQueue: queue, startImmediately: true)
                    }

                    observer = try reader.add(
                        observation: observation,
                        onError: { [unowned self] in self.receiveCompletion(.failure($0)) },
                        onChange: { [unowned self] in self.receive($0) })
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
        
        private func receive(_ value: Reducer.Value) {
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
        
        private func receiveSync(_ value: Reducer.Value) {
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
