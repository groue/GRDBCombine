import Combine
import Foundation
import GRDB

// TODO: It basically is a CurrentValueSubject. What can we learn from this?
@propertyDelegate
@dynamicMemberLookup
public class DatabasePublished<Value>: Publisher {
    public typealias Output = Value
    public typealias Failure = Error
    
    // TODO: replace with CurrentValueSubject when it is fixed.
    public var value: Result<Value, Error> { _value! }
    private var _value: Result<Value, Error>?
    private var subject = PassthroughSubject<Value, Error>()
    
    private var canceller: AnyCancellable!
    
    public convenience init<Reducer>(_ observation: ValueObservation<Reducer>, in reader: DatabaseReader)
        where Reducer: ValueReducer, Reducer.Value == Value
    {
        self.init(DatabasePublishers.Value(observation, in: reader))
    }
    
    public convenience init<Reducer>(_ publisher: DatabasePublishers.Value<Reducer>)
        where Reducer: ValueReducer, Reducer.Value == Value
    {
        self.init(publisher: publisher)
    }

    /// Intializer from any publisher that MUST emit its first element synchronously.
    private init<P>(publisher: P)
        where P: Publisher, P.Output == Value, P.Failure == Error
    {
        canceller = AnyCancellable(publisher.sink(
            receiveCompletion: { completion in
                switch completion {
                case let .failure(error):
                    // Make sure self.value is set before publishing
                    self._value = .failure(error)
                    self.subject.send(completion: completion)
                case .finished:
                    self.subject.send(completion: completion)
                }
        },
            receiveValue: { value in
                // Make sure self.value is set before publishing
                self._value = .success(value)
                self.subject.send(value)
        }))
        
        // TODO: can we avoid this check at compile time?
        if _value == nil {
            fatalError("Contract broken: observation did not emit its first element")
        }
    }
    
    public func receive<S>(subscriber: S)
        where S : Subscriber, S.Input == Value, S.Failure == Error
    {
        currentValuePublisher.receive(subscriber: subscriber)
    }
    
    private var currentValuePublisher: AnyPublisher<Value, Error> {
        do {
            let value = try self.value.get()
            return subject.prepend(value).eraseToAnyPublisher()
        } catch {
            return Publishers.Fail(error: error).eraseToAnyPublisher()
        }
    }
    
    public subscript<T>(dynamicMember keyPath: KeyPath<Value, T>) -> DatabasePublished<T> {
        DatabasePublished<T>(publisher: currentValuePublisher.map { $0[keyPath: keyPath] })
    }
}
