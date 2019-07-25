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
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(reader: DatabaseReader, label: String) {
            let expectation = self.expectation(description: label)
            let testCancellable = reader
                .readPublisher(value: { db in
                    try Player.fetchCount(db)
                })
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion, label: label)
                        expectation.fulfill()
                },
                    receiveValue: { value in
                        XCTAssertEqual(value, 1)
                })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
            .runInTemporaryDirectory("DatabaseSnapshot") { try prepare(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    // MARK: -
    
    func testReadPublisherError() throws {
        func test(reader: DatabaseReader, label: String) throws {
            let expectation = self.expectation(description: label)
            let testCancellable = reader
                .readPublisher(value: { db in
                    try Row.fetchAll(db, sql: "THIS IS NOT SQL")
                })
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertError(completion, label: label) { (error: DatabaseError) in
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
            .run("InMemoryDatabaseQueue") { DatabaseQueue() }
            .runInTemporaryDirectory("DatabaseQueue") { try DatabaseQueue(path: $0) }
            .runInTemporaryDirectory("DatabasePool") { try DatabasePool(path: $0) }
            .runInTemporaryDirectory("DatabaseSnapshot") { try DatabasePool(path: $0).makeSnapshot() }
    }
    
    // MARK: -
    
    func testReadPublisherDefaultScheduler() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(reader: DatabaseReader, label: String) {
            let expectation = self.expectation(description: label)
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
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
            .runInTemporaryDirectory("DatabaseSnapshot") { try prepare(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    // MARK: -
    
    func testReadPublisherCustomScheduler() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(reader: DatabaseReader, label: String) {
            let queue = DispatchQueue(label: "test")
            let expectation = self.expectation(description: label)
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
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
            .runInTemporaryDirectory("DatabaseSnapshot") { try prepare(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    // MARK: -
    
    func testReadPublisherIsReadonly() throws {
        func test(reader: DatabaseReader, label: String) throws {
            let expectation = self.expectation(description: label)
            let testCancellable = reader
                .readPublisher(value: { db in
                    try Player.createTable(db)
                })
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertError(completion, label: label) { (error: DatabaseError) in
                            XCTAssertEqual(error.resultCode, .SQLITE_READONLY)
                        }
                        expectation.fulfill()
                },
                    receiveValue: { _ in })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { DatabaseQueue() }
            .runInTemporaryDirectory("DatabaseQueue") { try DatabaseQueue(path: $0) }
            .runInTemporaryDirectory("DatabasePool") { try DatabasePool(path: $0) }
            .runInTemporaryDirectory("DatabaseSnapshot") { try DatabasePool(path: $0).makeSnapshot() }
    }
}
