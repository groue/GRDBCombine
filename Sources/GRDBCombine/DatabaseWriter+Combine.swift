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
        flatMapWritePublisher(receiveOn: scheduler) { db in
            try Just(updates(db)).setFailureType(to: Error.self)
        }
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
        flatMapWritePublisher(receiveOn: scheduler) { db -> AnyPublisher<Output, Error> in
            try self.concurrentReadPublisher(input: updates(db), value: value)
        }
    }
    
    // MARK: - Implementation
    
    private func flatMapWritePublisher<S, P>(
        receiveOn scheduler: S,
        updates: @escaping (Database) throws -> P)
        -> AnyPublisher<P.Output, Error>
        where S : Scheduler, P : Publisher, P.Failure == Error
    {
        OnDemandFuture<P, Error> { fulfill in
            self.asyncWriteWithoutTransaction { db in
                do {
                    var publisher: P? = nil
                    try db.inTransaction {
                        publisher = try updates(db)
                        return .commit
                    }
                    // Support for writePublisher(updates:thenRead:):
                    // fulfill after transaction, but still in the database
                    // writer queue.
                    fulfill(.success(publisher!))
                } catch {
                    fulfill(.failure(error))
                }
            }
        }
        .flatMap(maxPublishers: .unlimited, { $0 })
        .receiveValues(on: scheduler)
        .eraseToAnyPublisher()
    }
    
    private func concurrentReadPublisher<T, Output>(
        input: T,
        value: @escaping (Database, T) throws -> Output)
        -> AnyPublisher<Output, Error>
    {
        OnDemandFuture { fulfill in
            self.spawnConcurrentRead { dbResult in
                fulfill(dbResult.flatMap { db in Result { try value(db, input) } })
            }
        }
        .eraseToAnyPublisher()
    }
}
