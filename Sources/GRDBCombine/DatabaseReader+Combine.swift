import Combine
import Dispatch
import Foundation
import GRDB

/// Combine extensions on [DatabaseReader](https://github.com/groue/GRDB.swift/blob/master/README.md#databasewriter-and-databasereader-protocols).
extension DatabaseReader {
    /// Returns a Publisher that asynchronously completes with a fetched value.
    ///
    ///     // DatabasePublishers.Read<[Player]>
    ///     let players = dbQueue.readPublisher { db in
    ///         try Player.fetchAll(db)
    ///     }
    ///
    /// Its value and completion are emitted on the main dispatch queue.
    ///
    /// - parameter value: A closure which accesses the database.
    public func readPublisher<Output>(
        value: @escaping (Database) throws -> Output)
        -> DatabasePublishers.Read<Output>
    {
        readPublisher(receiveOn: DispatchQueue.main, value: value)
    }
    
    /// Returns a Publisher that asynchronously completes with a fetched value.
    ///
    ///     // DatabasePublishers.Read<[Player]>
    ///     let players = dbQueue.readPublisher(
    ///         receiveOn: DispatchQueue.global(),
    ///         value: { db in try Player.fetchAll(db) })
    ///
    /// Its value and completion are emitted on `scheduler`.
    ///
    /// - parameter scheduler: A Combine Scheduler.
    /// - parameter value: A closure which accesses the database.
    public func readPublisher<S, Output>(
        receiveOn scheduler: S,
        value: @escaping (Database) throws -> Output)
        -> DatabasePublishers.Read<Output>
        where S : Scheduler
    {
        Deferred {
            Future { fulfill in
                self.asyncRead { dbResult in
                    fulfill(dbResult.flatMap { db in Result { try value(db) } })
                }
            }
        }
        .receiveValues(on: scheduler)
        .eraseToReadPublisher()
    }
}

extension DatabasePublishers {
    /// A publisher that reads a value from the database. It publishes exactly
    /// one element, or an error.
    ///
    /// See:
    ///
    /// - `DatabaseReader.readPublisher(receiveOn:value:)`.
    /// - `DatabaseReader.readPublisher(value:)`.
    public struct Read<Output>: Publisher {
        public typealias Output = Output
        public typealias Failure = Error
        
        fileprivate let upstream: AnyPublisher<Output, Error>
        
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            upstream.receive(subscriber: subscriber)
        }
    }
}

extension Publisher where Failure == Error {
    fileprivate func eraseToReadPublisher() -> DatabasePublishers.Read<Output> {
        .init(upstream: eraseToAnyPublisher())
    }
}
