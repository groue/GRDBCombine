import Combine
import Dispatch
import Foundation
import GRDB

/// Combine extensions on [DatabaseReader](https://github.com/groue/GRDB.swift/blob/master/README.md#databasewriter-and-databasereader-protocols).
extension DatabaseReader {
    /// Returns a Publisher that asynchronously completes with a fetched value.
    ///
    ///     // AnyPublisher<[Player], Error>
    ///     let players = dbQueue.readPublisher { db in
    ///         try Player.fetchAll(db)
    ///     }
    ///
    /// Its value and completion are emitted on the main dispatch queue.
    ///
    /// - parameter value: A closure which accesses the database.
    public func readPublisher<Output>(
        value: @escaping (Database) throws -> Output)
        -> AnyPublisher<Output, Error>
    {
        readPublisher(receiveOn: DispatchQueue.main, value: value)
    }
    
    /// Returns a Publisher that asynchronously completes with a fetched value.
    ///
    ///     // AnyPublisher<[Player], Error>
    ///     let players = dbQueue.readPublisher(
    ///         receiveOn: DispatchQueue.global(),
    ///         value: { db in try Player.fetchAll(db) })
    ///
    /// Its value and completion are emitted on `scheduler`.
    ///
    /// - parameter scheduler: A Scheduler.
    /// - parameter value: A closure which accesses the database.
    public func readPublisher<S, Output>(
        receiveOn scheduler: S,
        value: @escaping (Database) throws -> Output)
        -> AnyPublisher<Output, Error>
        where S : Scheduler
    {
        DatabasePublishers.DeferredFuture({ fulfill in
            self.asyncRead { db in
                do {
                    try fulfill(Result.success(value(db.get())))
                } catch {
                    fulfill(Result.failure(error))
                }
            }
        })
            .receive(on: scheduler)
            .eraseToAnyPublisher()
    }
}
