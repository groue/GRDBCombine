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

class DatabaseWriterWritePublisherTests : XCTestCase {
    
    // MARK: -
    
    func testWritePublisher() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter) {
            try XCTAssertEqual(writer.read(Player.fetchCount), 0)
            let expectation = self.expectation(description: "")
            let testCancellable = writer
                .writePublisher(updates: { db in
                    try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                })
                .sink(
                    receiveCompletion: { completion in
                        assertNoFailure(completion)
                        expectation.fulfill()
                },
                    receiveValue: { _ in })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            
            try XCTAssertEqual(writer.read(Player.fetchCount), 1)
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testWritePublisherValue() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter) {
            let expectation = self.expectation(description: "")
            let testCancellable = writer
                .writePublisher(updates: { db -> Int in
                    try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                    return try Player.fetchCount(db)
                })
                .sink(
                    receiveCompletion: { completion in
                        assertNoFailure(completion)
                        expectation.fulfill()
                },
                    receiveValue: { count in
                        XCTAssertEqual(count, 1)
                })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testWritePublisherError() throws {
        func test(writer: DatabaseWriter) {
            let expectation = self.expectation(description: "")
            let testCancellable = writer
                .writePublisher(updates: { db in
                    try db.execute(sql: "THIS IS NOT SQL")
                })
                .sink(
                    receiveCompletion: { completion in
                        assertFailure(completion) { (error: DatabaseError) in
                            XCTAssertEqual(error.resultCode, .SQLITE_ERROR)
                            XCTAssertEqual(error.sql, "THIS IS NOT SQL")
                        }
                        expectation.fulfill()
                },
                    receiveValue: { _ in })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
        }
        
        try Test(test)
            .run { DatabaseQueue() }
            .runAtTemporaryDatabasePath { try DatabaseQueue(path: $0) }
            .runAtTemporaryDatabasePath { try DatabasePool(path: $0) }
    }
    
    // MARK: -
    
    func testWritePublisherDefaultScheduler() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter) {
            let expectation = self.expectation(description: "")
            let testCancellable = writer
                .writePublisher(updates: { db in
                    try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                })
                .sink(
                    receiveCompletion: { completion in
                        dispatchPrecondition(condition: .onQueue(.main))
                        expectation.fulfill()
                },
                    receiveValue: { _ in
                        dispatchPrecondition(condition: .onQueue(.main))
                })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testWritePublisherCustomScheduler() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter) {
            let queue = DispatchQueue(label: "test")
            let expectation = self.expectation(description: "")
            let testCancellable = writer
                .writePublisher(receiveOn: queue, updates: { db in
                    try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                })
                .sink(
                    receiveCompletion: { completion in
                        dispatchPrecondition(condition: .onQueue(queue))
                        expectation.fulfill()
                },
                    receiveValue: { _ in
                        dispatchPrecondition(condition: .onQueue(queue))
                })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    // TODO: Fix flaky test with both pool and on-disk queue:
    // - Expectation timeout
    func testWriteThenReadPublisher() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter) {
            let expectation = self.expectation(description: "")
            let testCancellable = writer
                .writePublisher(
                    updates: { db in try Player(id: 1, name: "Arthur", score: 1000).insert(db) },
                    thenRead: { db, _ in try Player.fetchCount(db) })
                .sink(
                    receiveCompletion: { completion in
                        assertNoFailure(completion)
                        expectation.fulfill()
                },
                    receiveValue: { count in
                        XCTAssertEqual(count, 1)
                })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testWriteThenReadPublisherWriteError() throws {
        func test(writer: DatabaseWriter) {
            let expectation = self.expectation(description: "")
            let testCancellable = writer
                .writePublisher(
                    updates: { db in try db.execute(sql: "THIS IS NOT SQL") },
                    thenRead: { _, _ in XCTFail("Should not read") })
                .sink(
                    receiveCompletion: { completion in
                        assertFailure(completion) { (error: DatabaseError) in
                            XCTAssertEqual(error.resultCode, .SQLITE_ERROR)
                            XCTAssertEqual(error.sql, "THIS IS NOT SQL")
                        }
                        expectation.fulfill()
                },
                    receiveValue: { _ in })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
        }
        
        try Test(test)
            .run { DatabaseQueue() }
            .runAtTemporaryDatabasePath { try DatabaseQueue(path: $0) }
            .runAtTemporaryDatabasePath { try DatabasePool(path: $0) }
    }
    
    // MARK: -
    
    // TODO: Fix flaky test with both pool and on-disk queue:
    // - Expectation timeout
    func testWriteThenReadPublisherReadError() throws {
        func test(writer: DatabaseWriter) {
            let expectation = self.expectation(description: "")
            let testCancellable = writer
                .writePublisher(
                    updates: { _ in },
                    thenRead: { db, _ in try Row.fetchAll(db, sql: "THIS IS NOT SQL") })
                .sink(
                    receiveCompletion: { completion in
                        assertFailure(completion) { (error: DatabaseError) in
                            XCTAssertEqual(error.resultCode, .SQLITE_ERROR)
                            XCTAssertEqual(error.sql, "THIS IS NOT SQL")
                        }
                        expectation.fulfill()
                },
                    receiveValue: { _ in })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
        }
        
        try Test(test)
            .run { DatabaseQueue() }
            .runAtTemporaryDatabasePath { try DatabaseQueue(path: $0) }
            .runAtTemporaryDatabasePath { try DatabasePool(path: $0) }
    }
}
