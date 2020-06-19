import Combine
import Dispatch
import GRDB

/// Combine extensions on [DatabaseWriter](https://github.com/groue/GRDB.swift/blob/master/README.md#databasewriter-and-databasereader-protocols).
extension DatabaseWriter {
    /// Returns a Publisher that asynchronously writes into the database.
    ///
    ///     // DatabasePublishers.Write<Int>
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
        -> DatabasePublishers.Write<Output>
    {
        writePublisher(receiveOn: DispatchQueue.main, updates: updates)
    }
    
    /// Returns a Publisher that asynchronously writes into the database.
    ///
    ///     // DatabasePublishers.Write<Int>
    ///     let newPlayerCount = dbQueue.writePublisher(
    ///         receiveOn: DispatchQueue.global(),
    ///         updates: { db -> Int in
    ///             try Player(...).insert(db)
    ///             return try Player.fetchCount(db)
    ///         })
    ///
    /// Its value and completion are emitted on `scheduler`.
    ///
    /// - parameter scheduler: A Combine Scheduler.
    /// - parameter updates: A closure which writes in the database.
    public func writePublisher<S, Output>(
        receiveOn scheduler: S,
        updates: @escaping (Database) throws -> Output)
        -> DatabasePublishers.Write<Output>
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
            .eraseToWritePublisher()
    }
    
    /// Returns a Publisher that asynchronously writes into the database.
    ///
    ///     // DatabasePublishers.Write<Int>
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
        -> DatabasePublishers.Write<Output>
    {
        writePublisher(receiveOn: DispatchQueue.main, updates: updates, thenRead: value)
    }
    
    
    /// Returns a Publisher that asynchronously writes into the database.
    ///
    ///     // DatabasePublishers.Write<Int>
    ///     let newPlayerCount = dbQueue.writePublisher(
    ///         receiveOn: DispatchQueue.global(),
    ///         updates: { db in try Player(...).insert(db) }
    ///         thenRead: { db, _ in try Player.fetchCount(db) })
    ///
    /// Its value and completion are emitted on `scheduler`.
    ///
    /// - parameter scheduler: A Combine Scheduler.
    /// - parameter updates: A closure which writes in the database.
    /// - parameter value: A closure which reads from the database.
    public func writePublisher<S, T, Output>(
        receiveOn scheduler: S,
        updates: @escaping (Database) throws -> T,
        thenRead value: @escaping (Database, T) throws -> Output)
        -> DatabasePublishers.Write<Output>
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
            .eraseToWritePublisher()
    }
}

extension DatabasePublishers {
    /// A publisher that writes into the database. It publishes exactly
    /// one element, or an error.
    ///
    /// See:
    ///
    /// - `DatabaseReader.writePublisher(updates:)`.
    /// - `DatabaseReader.writePublisher(updates:thenRead:)`.
    /// - `DatabaseReader.writePublisher(receiveOn:updates:)`.
    /// - `DatabaseReader.writePublisher(receiveOn:updates:thenRead:)`.
    public struct Write<Output>: Publisher {
        public typealias Output = Output
        public typealias Failure = Error
        
        fileprivate let upstream: AnyPublisher<Output, Error>
        
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            upstream.receive(subscriber: subscriber)
        }
    }
}

extension Publisher where Failure == Error {
    fileprivate func eraseToWritePublisher() -> DatabasePublishers.Write<Output> {
        .init(upstream: eraseToAnyPublisher())
    }
}
