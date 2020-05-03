import Combine
import Dispatch
import GRDB

/// Combine extensions on [DatabaseWriter](https://github.com/groue/GRDB.swift/blob/master/README.md#databasewriter-and-databasereader-protocols).
extension DatabaseWriter {
    /// Returns a Publisher that asynchronously writes into the database.
    ///
    ///     // AnyPublisher<Int, Error>
    ///     let newPlayerCount = dbQueue.writePublisher { db -> Int in
    ///         try Player(...).insert(db)
    ///         return try Player.fetchCount(db)
    ///     }
    ///
    /// Its value and completion are emitted on the main dispatch queue.
    ///
    /// - parameter updates: A closure which writes in the database.
    public func writePublisher<Output>(
        updates: @escaping (Database) throws -> Output)
        -> AnyPublisher<Output, Error>
    {
        writePublisher(receiveOn: DispatchQueue.main, updates: updates)
    }
    
    /// Returns a Publisher that asynchronously writes into the database.
    ///
    ///     // AnyPublisher<Int, Error>
    ///     let newPlayerCount = dbQueue.writePublisher(
    ///         receiveOn: DispatchQueue.global(),
    ///         updates: { db -> Int in
    ///             try Player(...).insert(db)
    ///             return try Player.fetchCount(db)
    ///         })
    ///
    /// Its value and completion are emitted on `scheduler`.
    ///
    /// - parameter scheduler: A Scheduler.
    /// - parameter updates: A closure which writes in the database.
    public func writePublisher<S, Output>(
        receiveOn scheduler: S,
        updates: @escaping (Database) throws -> Output)
        -> AnyPublisher<Output, Error>
        where S : Scheduler
    {
        OnDemandFuture({ fulfill in
            self.asyncWrite(updates, completion: { _, result in
                fulfill(result)
            })
        })
            // We don't want users to process emitted values on a
            // database dispatch queue.
            .receiveValues(on: scheduler)
            .eraseToAnyPublisher()
    }
    
    /// Returns a Publisher that asynchronously writes into the database.
    ///
    ///     // AnyPublisher<Int, Error>
    ///     let newPlayerCount = dbQueue.writePublisher(
    ///         updates: { db in try Player(...).insert(db) }
    ///         thenRead: { db, _ in try Player.fetchCount(db) })
    ///
    /// Its value and completion are emitted on the main dispatch queue.
    ///
    /// - parameter updates: A closure which writes in the database.
    /// - parameter value: A closure which reads from the database.
    public func writePublisher<T, Output>(
        updates: @escaping (Database) throws -> T,
        thenRead value: @escaping (Database, T) throws -> Output)
        -> AnyPublisher<Output, Error>
    {
        writePublisher(receiveOn: DispatchQueue.main, updates: updates, thenRead: value)
    }
    
    
    /// Returns a Publisher that asynchronously writes into the database.
    ///
    ///     // AnyPublisher<Int, Error>
    ///     let newPlayerCount = dbQueue.writePublisher(
    ///         receiveOn: DispatchQueue.global(),
    ///         updates: { db in try Player(...).insert(db) }
    ///         thenRead: { db, _ in try Player.fetchCount(db) })
    ///
    /// Its value and completion are emitted on `scheduler`.
    ///
    /// - parameter scheduler: A Scheduler.
    /// - parameter updates: A closure which writes in the database.
    /// - parameter value: A closure which reads from the database.
    public func writePublisher<S, T, Output>(
        receiveOn scheduler: S,
        updates: @escaping (Database) throws -> T,
        thenRead value: @escaping (Database, T) throws -> Output)
        -> AnyPublisher<Output, Error>
        where S : Scheduler
    {
        OnDemandFuture({ fulfill in
            self.asyncWriteWithoutTransaction { db in
                var updatesValue: T?
                do {
                    try db.inTransaction {
                        updatesValue = try updates(db)
                        return .commit
                    }
                } catch {
                    fulfill(.failure(error))
                    return
                }
                self.spawnConcurrentRead { dbResult in
                    fulfill(dbResult.flatMap { db in Result { try value(db, updatesValue!) } })
                }
            }
        })
            // We don't want users to process emitted values on a
            // database dispatch queue.
            .receiveValues(on: scheduler)
            .eraseToAnyPublisher()
    }
}
