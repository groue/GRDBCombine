import GRDB
import Combine
import GRDBCombine
import XCTest

private struct Player: Codable, FetchableRecord, PersistableRecord {
    var id: Int64
    var name: String
    var score: Int?
    
    static func createTable(_ db: Database) throws {
        try db.create(table: "player") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("score", .integer)
        }
    }
}

class DatabasePublishersValueTests : XCTestCase {
    
    // MARK: -
    
    func testDatabasePublishersValue() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, label: String) throws {
            let expectation = self.expectation(description: label)
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .collect(3)
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion, label: label)
                },
                    receiveValue: { value in
                        XCTAssertEqual(value, [0, 1, 3])
                        expectation.fulfill()
                })
            
            let observationCancellable = Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .subscribe(testSubject)
            
            try writer.writeWithoutTransaction { db in
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                
                try db.inTransaction {
                    try Player(id: 2, name: "Barbara", score: 750).insert(db)
                    try Player(id: 3, name: "Craig", score: 500).insert(db)
                    return .commit
                }
            }
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            observationCancellable.cancel()
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runAtTemporaryDatabasePath("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testDatabasePublishersValueDefaultScheduler() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, label: String) throws {
            let expectation = self.expectation(description: label)
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .handleEvents(receiveOutput: { _ in
                    dispatchPrecondition(condition: .onQueue(.main))
                })
                .collect(2)
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion, label: label)
                        dispatchPrecondition(condition: .onQueue(.main))
                },
                    receiveValue: { value in
                        // 2 = test for initial value + changed value
                        XCTAssertEqual(value.count, 2)
                        expectation.fulfill()
                })
            
            let observationCancellable = Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .subscribe(testSubject)
            
            try writer.writeWithoutTransaction { db in
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            observationCancellable.cancel()
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runAtTemporaryDatabasePath("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testDatabasePublishersValueEmitsFirstValueAsynchronously() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, label: String) throws {
            let expectation = self.expectation(description: label)
            let semaphore = DispatchSemaphore(value: 0)
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { _ in
                        semaphore.wait()
                        expectation.fulfill()
                })
            
            let observationCancellable = Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .subscribe(testSubject)
            
            semaphore.signal()
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            observationCancellable.cancel()
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runAtTemporaryDatabasePath("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
    
    // MARK: - FetchOnSubscription
    
    func testDatabasePublishersValueFetchOnSubscription() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, label: String) throws {
            let expectation = self.expectation(description: label)
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .collect(3)
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion, label: label)
                },
                    receiveValue: { value in
                        XCTAssertEqual(value, [0, 1, 3])
                        expectation.fulfill()
                })
            
            let observationCancellable = Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .fetchOnSubscription()
                .subscribe(testSubject)
            
            try writer.writeWithoutTransaction { db in
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                
                try db.inTransaction {
                    try Player(id: 2, name: "Barbara", score: 750).insert(db)
                    try Player(id: 3, name: "Craig", score: 500).insert(db)
                    return .commit
                }
            }
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            observationCancellable.cancel()
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runAtTemporaryDatabasePath("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testDatabasePublishersValueFetchOnSubscriptionDefaultScheduler() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, label: String) throws {
            let expectation = self.expectation(description: label)
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .handleEvents(receiveOutput: { _ in
                    dispatchPrecondition(condition: .onQueue(.main))
                })
                .collect(2)
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion, label: label)
                        dispatchPrecondition(condition: .onQueue(.main))
                },
                    receiveValue: { value in
                        // 2 = test for initial value + changed value
                        XCTAssertEqual(value.count, 2)
                        expectation.fulfill()
                })
            
            let observationCancellable = Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .fetchOnSubscription()
                .subscribe(testSubject)
            
            try writer.writeWithoutTransaction { db in
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            observationCancellable.cancel()
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runAtTemporaryDatabasePath("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testDatabasePublishersValueFetchOnSubscriptionEmitsFirstValueSynchronously() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, label: String) throws {
            let semaphore = DispatchSemaphore(value: 0)
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { _ in
                        dispatchPrecondition(condition: .onQueue(.main))
                        semaphore.signal()
                })
            
            let observationCancellable = Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .fetchOnSubscription()
                .subscribe(testSubject)
            
            semaphore.wait()
            testCancellable.cancel()
            observationCancellable.cancel()
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runAtTemporaryDatabasePath("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
}
