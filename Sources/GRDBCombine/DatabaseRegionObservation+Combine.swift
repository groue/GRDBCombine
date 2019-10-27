import Combine
import Foundation
import GRDB

/// Combine extensions on [DatabaseRegionObservation](https://github.com/groue/GRDB.swift/blob/master/README.md#databaseregionobservation).
extension DatabaseRegionObservation {
    /// Returns a publisher that tracks changes in a database region.
    ///
    /// It emits database connections on a protected dispatch queue.
    ///
    /// Error completion, if any, is only emitted, synchronously,
    /// on subscription.
    public func publisher(in writer: DatabaseWriter) -> DatabasePublishers.DatabaseRegion {
        return DatabasePublishers.DatabaseRegion(self, in: writer)
    }
}

extension DatabasePublishers {
    /// A publisher that tracks changes in a database region.
    ///
    /// See `DatabaseRegionObservation.publisher(in:)`.
    public struct DatabaseRegion: Publisher {
        public typealias Output = Database
        public typealias Failure = Error
        
        let writer: DatabaseWriter
        let observation: DatabaseRegionObservation
        
        init(_ observation: DatabaseRegionObservation, in writer: DatabaseWriter) {
            self.writer = writer
            self.observation = observation
        }
        
        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
            let subscription = DatabaseRegionSubscription(
                writer: writer,
                observation: observation,
                downstream: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }
    
    private class DatabaseRegionSubscription<Downstream: Subscriber>: Subscription
        where Downstream.Failure == Error, Downstream.Input == Database
    {
        private struct WaitingForDemand {
            let downstream: Downstream
            let writer: DatabaseWriter
            let observation: DatabaseRegionObservation
        }
        
        private struct Observing {
            let downstream: Downstream
            let writer: DatabaseWriter // Retain writer until subscription is finished
            var remainingDemand: Subscribers.Demand
        }
        
        private enum State {
            // Waiting for demand, not observing the database.
            case waitingForDemand(WaitingForDemand)
            
            // Observing the database.
            case observing(Observing)
            
            // Completed or cancelled, not observing the database.
            case finished
        }
        
        // Observer is not stored in self.state because we must enter the
        // .observing state *before* the observation starts.
        private var observer: TransactionObserver?
        private var state: State
        private var lock = NSRecursiveLock() // Allow re-entrancy
        
        init(
            writer: DatabaseWriter,
            observation: DatabaseRegionObservation,
            downstream: Downstream)
        {
            state = .waitingForDemand(WaitingForDemand(
                downstream: downstream,
                writer: writer,
                observation: observation))
        }
        
        func request(_ demand: Subscribers.Demand) {
            lock.synchronized {
                switch state {
                case let .waitingForDemand(info):
                    guard demand > 0 else {
                        return
                    }
                    do {
                        state = .observing(Observing(
                            downstream: info.downstream,
                            writer: info.writer,
                            remainingDemand: demand))
                        observer = try info.observation.start(
                            in: info.writer,
                            onChange: { [weak self] in self?.receive($0) })
                    } catch {
                        state = .finished
                        info.downstream.receive(completion: .failure(error))
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
            lock.synchronized {
                observer = nil
                state = .finished
            }
        }
        
        private func receive(_ value: Database) {
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
    }
}
