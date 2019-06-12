import Combine
import Foundation
import GRDB

extension DatabasePublishers {
    /// A publisher that tracks changes in a database region.
    ///
    /// It emits database connections on a protected dispatch queue.
    ///
    /// Error completion, if any, is only emitted, synchronously,
    /// on subscription.
    public struct DatabaseRegion: Publisher {
        public typealias Output = Database
        public typealias Failure = Error
        
        let writer: DatabaseWriter
        let observation: DatabaseRegionObservation
        
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
            // Waiting for demand, not observing the database.
            case waitingForDemand
            
            // Observing the database. Self.observer is not nil.
            // Demand is the remaining demand.
            case observing(Subscribers.Demand)
            
            // Completed or cancelled, not observing the database.
            case finished
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
            lock.synchronized {
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
        
        private func receive(_ value: Database) {
            lock.synchronized {
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
        }
        
        private func receiveCompletion(_ completion: Subscribers.Completion<Error>) {
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
