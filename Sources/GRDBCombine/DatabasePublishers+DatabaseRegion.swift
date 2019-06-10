import Combine
import Foundation
import GRDB

extension DatabasePublishers {
    /// A publisher that tracks changes in a database region
    public struct DatabaseRegion: Publisher {
        public typealias Output = Database
        public typealias Failure = Error
        
        let writer: DatabaseWriter
        let observation: DatabaseRegionObservation
        
        // TODO
        // - initializer from multiple regions
        public init(_ observation: DatabaseRegionObservation, in writer: DatabaseWriter) {
            self.writer = writer
            self.observation = observation
        }
        
        public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
            let subscription = DatabaseRegionSubscription(
                writer: writer,
                observation: observation,
                receiveCompletion: subscriber.receive(completion:),
                receive: subscriber.receive(_:))
            subscriber.receive(subscription: subscription)
        }
    }
    
    private class DatabaseRegionSubscription: Subscription {
        private enum State {
            case waitingForDemand
            case observing(Subscribers.Demand)
            case completed
            case cancelled
        }
        private let writer: DatabaseWriter
        private let observation: DatabaseRegionObservation
        private let _receiveCompletion: (Subscribers.Completion<Error>) -> Void
        private let _receive: (Database) -> Subscribers.Demand
        private var observer: TransactionObserver?
        private var state: State = .waitingForDemand
        private var lock = NSRecursiveLock() // Allow re-entrancy
        
        init(
            writer: DatabaseWriter,
            observation: DatabaseRegionObservation,
            receiveCompletion: @escaping (Subscribers.Completion<Error>) -> Void,
            receive: @escaping (Database) -> Subscribers.Demand)
        {
            self.writer = writer
            self.observation = observation
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
                state = .observing(demand)
                do {
                    observer = try observation.start(
                        in: writer,
                        onChange: { [unowned self] in self.receive($0) })
                } catch {
                    receiveCompletion(.failure(error))
                }
            
            case let .observing(currentDemand):
                state = .observing(currentDemand + demand)
            
            case .completed:
                break
            
            case .cancelled:
                break
            }
        }
        
        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            
            observer = nil
            state = .cancelled
        }
        
        private func receive(_ value: Database) {
            lock.lock()
            defer { lock.unlock() }
            
            guard case .observing = state else {
                return
            }
            
            let additionalDemand = _receive(value)
            
            if case let .observing(demand) = state {
                let newDemand = demand + additionalDemand - 1
                if newDemand == .none {
                    observer = nil
                    state = .waitingForDemand
                } else {
                    state = .observing(newDemand)
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
