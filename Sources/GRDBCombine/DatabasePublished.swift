import Combine
import Foundation
import GRDB

/// DatabasePublished is a property wrapper whose value automatically changes,
/// on the main queue, when the database is modified.
///
/// Usage:
///
///     class MyModel {
///         // A DatabasePublishers.Value
///         static let playersPublisher = Player.observationForAll().publisher(in: dbQueue)
///
///         @DatabasePublished(playersPublisher)
///         var players: Result<[Players], Error>
///     }
///
///     let model = MyModel()
///     try model.players.get() // [Player]
///     model.$players          // Publisher of output [Player], failure Error
///
/// By default, the initial value of the property is immediately fetched from
/// the database. This blocks your main queue until the database access
/// completes.
///
/// You can opt in for an asynchronous fetching by providing an initial value:
///
///     class MyModel {
///         // The initialValue argument triggers asynchronous fetching
///         @DatabasePublished(initialValue: [], playersPublisher)
///         var players: Result<[Players], Error>
///     }
///
///     let model = MyModel()
///     // Empty array until the initial fetch is performed
///     try model.players.get()
///
/// DatabasePublished is a [reference type](https://developer.apple.com/swift/blog/?id=10)
/// which tracks changes the database during its whole life time. It is not
/// advised to use it in a value type such as a struct.
@propertyWrapper
public class DatabasePublished<Output>: Publisher {
    public typealias Output = Output
    public typealias Failure = Error
    
    /// The freshest value.
    ///
    /// - warning: this property is not thread-safe and must be used from the
    ///   main queue only.
    public var wrappedValue: Result<Output, Error> { _result! }
    
    /// A publisher that emits an event whenever the value changes.
    ///
    /// - warning: The type of this property will change. Only rely on the fact
    ///   that it is a Publisher.
    public let didChange = PassthroughSubject<Void, Never>() // Support for SwiftUI
    private var _result: Result<Output, Error>?
    private var subject = PassthroughSubject<Output, Error>()
    
    private var canceller: AnyCancellable!
    
    /// Creates a property wrapper whose value automatically changes when the
    /// database is modified.
    ///
    /// It must be instantiated from the main queue, or you will get a
    /// fatal error.
    ///
    /// Its value is eventually updated on the main queue after each
    /// database change.
    public convenience init(_ publisher: DatabasePublishers.Value<Output>) {
        // Safe because publisher fetches on subscription
        self.init(
            initialResult: nil,
            unsafePublisher: publisher.fetchOnSubscription().eraseToResult())
    }
    
    /// Creates a property wrapper whose value automatically changes when the
    /// database is modified.
    ///
    /// Its value is eventually updated on the main queue after each
    /// database change.
    public convenience init(initialValue: Output, _ publisher: DatabasePublishers.Value<Output>) {
        // Safe because initialResult is not nil
        self.init(
            initialResult: .success(initialValue),
            unsafePublisher: publisher.eraseToResult())
    }
    
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
    
    /// :nodoc:
    public func receive<S>(subscriber: S)
        where S : Subscriber, S.Input == Output, S.Failure == Error
    {
        currentValuePublisher.receive(subscriber: subscriber)
    }
    
    private var currentValuePublisher: AnyPublisher<Output, Error> {
        switch wrappedValue {
        case let .success(value):
            return subject.prepend(value).eraseToAnyPublisher()
        case let .failure(error):
            return Publishers.Fail<Output, Error>(error: error).eraseToAnyPublisher()
        }
    }
}

#if canImport(SwiftUI)
import SwiftUI
extension DatabasePublished: BindableObject { }
#endif
