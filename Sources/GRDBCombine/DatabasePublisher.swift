import Combine
import Foundation
import GRDB

public struct DatabasePublisher<Reducer: ValueReducer>: Publisher {
    public typealias Output = Reducer.Value
    public typealias Failure = Error
    
    let reader: DatabaseReader
    let observation: ValueObservation<Reducer>
    
    public init(for observation: ValueObservation<Reducer>, in reader: DatabaseReader) {
        self.reader = reader
        self.observation = observation
    }
    
    public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = DatabaseSubscription<Reducer>(
            reader: reader,
            observation: observation,
            receiveCompletion: subscriber.receive(completion:),
            receive: subscriber.receive(_:))
        subscriber.receive(subscription: subscription)
    }
}

private class DatabaseSubscription<Reducer: ValueReducer>: Subscription {
    private enum State {
        case waitingForDemand
        case observing(Subscribers.Demand)
        case completed
        case cancelled
    }
    private let reader: DatabaseReader
    private let observation: ValueObservation<Reducer>
    private let _receiveCompletion: (Subscribers.Completion<Error>) -> Void
    private let _receive: (Reducer.Value) -> Subscribers.Demand
    private var observer: TransactionObserver?
    private var state: State = .waitingForDemand
    private var lock = NSRecursiveLock() // Allow re-entrancy
    
    init(
        reader: DatabaseReader,
        observation: ValueObservation<Reducer>,
        receiveCompletion: @escaping (Subscribers.Completion<Error>) -> Void,
        receive: @escaping (Reducer.Value) -> Subscribers.Demand)
    {
        self.reader = reader
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
                observer = try reader.add(
                    observation: observation,
                    onError: { [unowned self] in self.receiveCompletion(.failure($0)) },
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
    
    private func receive(_ value: Reducer.Value) {
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
