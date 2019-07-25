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
            Result(catching: { try updates(db) }).publisher
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
            do {
                return try self.concurrentReadPublisher(input: updates(db), value: value)
            } catch {
                return Fail(error: error).eraseToAnyPublisher()
            }
        }
    }
    
    // MARK: - Implementation
    
    private func flatMapWritePublisher<S, P>(
        receiveOn scheduler: S,
        updates: @escaping (Database) throws -> P)
        -> AnyPublisher<P.Output, Error>
        where S : Scheduler, P : Publisher, P.Failure == Error
    {
        Deferred {
            Future<P, Error> { fulfill in
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
        }
            // ? Tests for writePublisher(updates:thenRead:) fail
            // without .unlimited
            .flatMap(maxPublishers: .unlimited, { $0 })
            .buffer(size: 1, prefetch: .keepFull, whenFull: .dropOldest)
            .receive(on: scheduler)
            .eraseToAnyPublisher()
    }
    
    private func concurrentReadPublisher<T, Output>(
        input: T,
        value: @escaping (Database, T) throws -> Output)
        -> AnyPublisher<Output, Error>
    {
        Deferred {
            Future { fulfill in
                self.spawnConcurrentRead { db in
                    fulfill(Result {
                        try value(db.get(), input)
                    })
                }
            }
            .buffer(size: 1, prefetch: .keepFull, whenFull: .dropOldest)
        }
        .eraseToAnyPublisher()
    }
}
