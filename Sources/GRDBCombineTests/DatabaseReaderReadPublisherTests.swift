import GRDB
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

class DatabaseReaderReadPublisherTests : XCTestCase {
    
    // MARK: -
    
    func testReadPublisher() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(reader: DatabaseReader) {
            let expectation = self.expectation(description: "")
            let testCancellable = reader
                .readPublisher(value: { db in
                    try Player.fetchCount(db)
                })
                .sink(
                    receiveCompletion: { completion in
                        assertNoFailure(completion)
                        expectation.fulfill()
                },
                    receiveValue: { value in
                        XCTAssertEqual(value, 1)
                })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    // MARK: -
    
    func testReadPublisherError() throws {
        func test(reader: DatabaseReader) throws {
            let expectation = self.expectation(description: "")
            let testCancellable = reader
                .readPublisher(value: { db in
                    try Row.fetchAll(db, sql: "THIS IS NOT SQL")
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
            .runAtTemporaryDatabasePath { try DatabasePool(path: $0).makeSnapshot() }
    }
    
    // MARK: -
    
    func testReadPublisherDefaultScheduler() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(reader: DatabaseReader) {
            let expectation = self.expectation(description: "")
            let testCancellable = reader
                .readPublisher(value: { db in
                    try Player.fetchCount(db)
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
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    // MARK: -
    
    func testReadPublisherCustomScheduler() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(reader: DatabaseReader) {
            let queue = DispatchQueue(label: "test")
            let expectation = self.expectation(description: "")
            let testCancellable = reader
                .readPublisher(receiveOn: queue, value: { db in
                    try Player.fetchCount(db)
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
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    // MARK: -
    
    func testReadPublisherIsReadonly() throws {
        func test(reader: DatabaseReader) throws {
            let expectation = self.expectation(description: "")
            let testCancellable = reader
                .readPublisher(value: { db in
                    try Player.createTable(db)
                })
                .sink(
                    receiveCompletion: { completion in
                        assertFailure(completion) { (error: DatabaseError) in
                            XCTAssertEqual(error.resultCode, .SQLITE_READONLY)
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
            .runAtTemporaryDatabasePath { try DatabasePool(path: $0).makeSnapshot() }
    }
}
