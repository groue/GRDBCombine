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
    
//    // TODO: useful?
//    public convenience init<P>(_ publisher: P)
//        where P: Publisher, P.Output == Result<Output, Failure>, P.Failure == Never, Output: ExpressibleByNilLiteral
//    {
//        self.init(publisher, initial: nil)
//    }
//
//    // TODO: useful?
//    convenience init<P>(_ publisher: P, initial: Output)
//        where P: Publisher, P.Output == Result<Output, Failure>, P.Failure == Never
//    {
//        // Safe because initial is not nil
//        self.init(unsafe: publisher, initialResult: .success(initial))
//    }
    
    /// Unsafe initializer which fatalError if initial is nil and publisher
    /// does not emit its first value synchronously.
    init<P>(initialResult: Result<Output, Failure>?, unsafePublisher publisher: P)
        where P: Publisher, P.Output == Result<Output, Failure>, P.Failure == Never
    {
        _result = initialResult
        
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
        // Safe because initialResult is not nil
        DatabasePublished<T, Failure>(
            initialResult: value.map { $0[keyPath: keyPath] },
            unsafePublisher: currentValuePublisher.map { $0[keyPath: keyPath] }.eraseToResult())
    }
}

extension DatabasePublished where Failure == Error {
//    // TODO: useful?
//    public convenience init<Reducer>(
//        _ observation: ValueObservation<Reducer>,
//        in reader: DatabaseReader,
//        initial: Output)
//        where Reducer: ValueReducer, Reducer.Value == Output, Output: ExpressibleByNilLiteral
//    {
//        self.init(
//            DatabasePublishers.Value(observation, in: reader),
//            initial: initial)
//    }
//    
//    // TODO: useful?
//    public convenience init<Reducer>(
//        _ observation: ValueObservation<Reducer>,
//        in reader: DatabaseReader)
//        where Reducer: ValueReducer, Reducer.Value == Output, Output: ExpressibleByNilLiteral
//    {
//        self.init(DatabasePublishers.Value(observation, in: reader))
//    }
    
    public convenience init(
        _ publisher: DatabasePublishers.Value<Output>)
    {
        // Safe because publisher fetches on subscription
        self.init(
            initialResult: nil,
            unsafePublisher: publisher.fetchOnSubscription().eraseToResult())
    }
    
    public convenience init(
        initialValue: Output,
        _ publisher: DatabasePublishers.Value<Output>)
    {
        // Safe because initialResult is not nil
        self.init(
            initialResult: .success(initialValue),
            unsafePublisher: publisher.eraseToResult())
    }
}
