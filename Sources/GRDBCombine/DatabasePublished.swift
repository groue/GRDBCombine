import Combine
import Foundation
import GRDB

@propertyDelegate
@dynamicMemberLookup
public class DatabasePublished<Output>: Publisher {
    public typealias Output = Output
    public typealias Failure = Error
    
    public var value: Result<Output, Error> { _result! }
    private var _result: Result<Output, Error>?
    private var subject = PassthroughSubject<Output, Error>()
    public var didChange = PassthroughSubject<Void, Never>() // Support for SwiftUI
    
    private var canceller: AnyCancellable!
    
    /// Unsafe initializer which fatalError if initial is nil and publisher
    /// does not emit its first value synchronously.
    init<P>(initialResult: Result<Output, Error>?, unsafePublisher publisher: P)
        where P: Publisher, P.Output == Result<Output, Error>, P.Failure == Never
    {
        _result = initialResult
        
        canceller = AnyCancellable(publisher.sink(
            receiveCompletion: { completion in
                switch completion {
                case .finished:
                    self.didChange.send(())
                    self.subject.send(completion: .finished)
                }
        },
            receiveValue: { result in
                // Make sure self.value is set before publishing
                self._result = result
                switch result {
                case let .success(value):
                    self.didChange.send(())
                    self.subject.send(value)
                case let .failure(error):
                    self.didChange.send(())
                    self.subject.send(completion: .failure(error))
                }
        }))
        
        if _result == nil {
            fatalError("Contract broken: observation did not emit its first element")
        }
    }
    
    public func receive<S>(subscriber: S)
        where S : Subscriber, S.Input == Output, S.Failure == Error
    {
        currentValuePublisher.receive(subscriber: subscriber)
    }
    
    private var currentValuePublisher: AnyPublisher<Output, Error> {
        switch value {
        case let .success(value):
            return subject.prepend(value).eraseToAnyPublisher()
        case let .failure(error):
            return Publishers.Fail<Output, Error>(error: error).eraseToAnyPublisher()
        }
    }
    
    public subscript<T>(dynamicMember keyPath: KeyPath<Output, T>) -> DatabasePublished<T> {
        // Safe because initialResult is not nil
        DatabasePublished<T>(
            initialResult: value.map { $0[keyPath: keyPath] },
            unsafePublisher: currentValuePublisher.map { $0[keyPath: keyPath] }.eraseToResult())
    }
}

extension DatabasePublished {
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

#if canImport(SwiftUI)
import SwiftUI
extension DatabasePublished: BindableObject { }
#endif
