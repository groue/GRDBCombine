import Combine
import Foundation
import GRDB

@propertyDelegate
@dynamicMemberLookup
public class DatabasePublished<Output, Failure: Error>: Publisher {
    public var value: Result<Output, Failure> { _result! }
    private var _result: Result<Output, Failure>?
    private var subject = PassthroughSubject<Output, Failure>()
    
    private var canceller: AnyCancellable!
    
    public convenience init<P>(_ publisher: P)
        where P: Publisher, P.Output == Result<Output, Failure>, P.Failure == Never, Output: ExpressibleByNilLiteral
    {
        self.init(publisher, initial: .success(nil))
    }
    
    public convenience init<P>(_ publisher: P, initial: Result<Output, Failure>)
        where P: Publisher, P.Output == Result<Output, Failure>, P.Failure == Never
    {
        // Safe because initial is not nil
        self.init(unsafe: publisher, initial: initial)
    }

    init<P>(unsafe publisher: P, initial: Result<Output, Failure>?)
        where P: Publisher, P.Output == Result<Output, Failure>, P.Failure == Never
    {
        _result = initial
        
        canceller = AnyCancellable(publisher.sink(
            receiveCompletion: { completion in
                switch completion {
                case .finished:
                    self.subject.send(completion: .finished)
                }
        },
            receiveValue: { result in
                // Make sure self.value is set before publishing
                self._result = result
                switch result {
                case let .success(value):
                    self.subject.send(value)
                case let .failure(error):
                    self.subject.send(completion: .failure(error))
                }
        }))
        
        if _result == nil {
            fatalError("Contract broken: observation did not emit its first element")
        }
    }
    
    public func receive<S>(subscriber: S)
        where S : Subscriber, S.Input == Output, S.Failure == Failure
    {
        currentValuePublisher.receive(subscriber: subscriber)
    }
    
    private var currentValuePublisher: AnyPublisher<Output, Failure> {
        switch value {
        case let .success(value):
            return subject.prepend(value).eraseToAnyPublisher()
        case let .failure(error):
            return Publishers.Fail<Output, Failure>(error: error).eraseToAnyPublisher()
        }
    }
    
    public subscript<T>(dynamicMember keyPath: KeyPath<Output, T>) -> DatabasePublished<T, Failure> {
        DatabasePublished<T, Failure>(
            currentValuePublisher.map { $0[keyPath: keyPath] }.eraseToResult(),
            initial: value.map { $0[keyPath: keyPath] })
    }
}

extension DatabasePublished where Failure == Error {
    public convenience init<Reducer>(_ observation: ValueObservation<Reducer>, in reader: DatabaseReader)
        where Reducer: ValueReducer, Reducer.Value == Output, Output: ExpressibleByNilLiteral
    {
        self.init(DatabasePublishers.Value(observation, in: reader))
    }
    
    public convenience init<Reducer>(_ publisher: DatabasePublishers.Value<Reducer>)
        where Reducer: ValueReducer, Reducer.Value == Output
    {
        // TODO: make it safe by forcing it to publish its first element synchronously
        self.init(unsafe: publisher.eraseToResult(), initial: nil)
    }
}
