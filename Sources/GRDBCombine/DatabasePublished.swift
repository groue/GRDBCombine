import Combine
import Foundation
import GRDB

@propertyDelegate
@dynamicMemberLookup
public class DatabasePublished<Value>: Publisher {
    public typealias Output = Result<Value, Error>
    public typealias Failure = Never
    
    // TODO: replace with CurrentValueSubject when it is fixed.
    public var value: Output { _value! }
    private var _value: Output?
    private var subject = PassthroughSubject<Output, Failure>()
    
    private var canceller: AnyCancellable!
    
    public init<Reducer>(_ observation: ValueObservation<Reducer>, in reader: DatabaseReader)
        where Reducer: ValueReducer, Reducer.Value == Value
    {
        canceller = AnyCancellable(DatabasePublisher(for: observation, in: reader)
            .map { Result.success($0) }
            .catch { Publishers.Just(.failure($0)) }
            .sink { [unowned self] value in
                // Make sure self.value is set before publishing
                self._value = value
                self.subject.send(value)
        })
        
        // TODO: can we avoid this check at compile time?
        if _value == nil {
            fatalError("Contract broken: observation did not emit its first element")
        }
    }
    
    public func receive<S>(subscriber: S)
        where S : Subscriber, S.Failure == Failure, S.Input == Output
    {
        subject
            .prepend(Publishers.Just(value))
            .receive(subscriber: subscriber)
    }
    
    public subscript<T>(dynamicMember keyPath: KeyPath<Value, T>) -> AnyPublisher<T, Error> {
        return subject
            .prepend(Publishers.Just(value))
            .tryMap { try $0.get()[keyPath: keyPath ] }
            .eraseToAnyPublisher()
    }
}
