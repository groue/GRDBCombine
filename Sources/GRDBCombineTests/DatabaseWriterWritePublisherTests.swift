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
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, cancelBag: CancelBag, label: String) {
            try XCTAssertEqual(writer.read(Player.fetchCount), 0)
            let expectation = self.expectation(description: label)
            writer
                .writePublisher { db in
                    try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                }
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion, label: label)
                        expectation.fulfill()
                },
                    receiveValue: { _ in })
                .add(to: cancelBag)
            waitForExpectations(timeout: 1, handler: nil)
            try XCTAssertEqual(writer.read(Player.fetchCount), 1)
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testWritePublisherValue() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, cancelBag: CancelBag, label: String) {
            let expectation = self.expectation(description: label)
            writer
                .writePublisher { db -> Int in
                    try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                    return try Player.fetchCount(db)
                }
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion, label: label)
                        expectation.fulfill()
                },
                    receiveValue: { count in
                        XCTAssertEqual(count, 1)
                })
                .add(to: cancelBag)
            waitForExpectations(timeout: 1, handler: nil)
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testWritePublisherError() throws {
        func test(writer: DatabaseWriter, cancelBag: CancelBag, label: String) {
            let expectation = self.expectation(description: label)
            writer
                .writePublisher { db in
                    try db.execute(sql: "THIS IS NOT SQL")
                }
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertError(completion, label: label) { (error: DatabaseError) in
                            XCTAssertEqual(error.resultCode, .SQLITE_ERROR)
                            XCTAssertEqual(error.sql, "THIS IS NOT SQL")
                        }
                        expectation.fulfill()
                },
                    receiveValue: { _ in })
                .add(to: cancelBag)
            waitForExpectations(timeout: 1, handler: nil)
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { DatabaseQueue() }
            // TODO: fix flacky test (unfulfilled expectation)
            .runInTemporaryDirectory("DatabaseQueue") { try DatabaseQueue(path: $0) }
            .runInTemporaryDirectory("DatabasePool") { try DatabasePool(path: $0) }
    }
    
    // MARK: -
    
    func testWritePublisherDefaultScheduler() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, cancelBag: CancelBag, label: String) {
            let expectation = self.expectation(description: label)
            writer
                .writePublisher { db in
                    try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                }
                .sink(
                    receiveCompletion: { completion in
                        dispatchPrecondition(condition: .onQueue(.main))
                        expectation.fulfill()
                },
                    receiveValue: { _ in
                        dispatchPrecondition(condition: .onQueue(.main))
                })
                .add(to: cancelBag)
            waitForExpectations(timeout: 1, handler: nil)
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testWritePublisherCustomScheduler() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, cancelBag: CancelBag, label: String) {
            let queue = DispatchQueue(label: "test")
            let expectation = self.expectation(description: label)
            writer
                .writePublisher(receiveOn: queue) { db in
                    try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                }
                .sink(
                    receiveCompletion: { completion in
                        dispatchPrecondition(condition: .onQueue(queue))
                        expectation.fulfill()
                },
                    receiveValue: { _ in
                        dispatchPrecondition(condition: .onQueue(queue))
                })
                .add(to: cancelBag)
            waitForExpectations(timeout: 1, handler: nil)
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testWriteThenReadPublisher() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter, cancelBag: CancelBag, label: String) {
            let expectation = self.expectation(description: label)
            writer
                .writePublisher(
                    updates: { db in try Player(id: 1, name: "Arthur", score: 1000).insert(db) },
                    thenRead: { db, _ in try Player.fetchCount(db) })
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion, label: label)
                        expectation.fulfill()
                },
                    receiveValue: { count in
                        XCTAssertEqual(count, 1)
                })
                .add(to: cancelBag)
            waitForExpectations(timeout: 1, handler: nil)
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
    }
    
    // MARK: -
    
    func testWriteThenReadPublisherWriteError() throws {
        func test(writer: DatabaseWriter, cancelBag: CancelBag, label: String) {
            let expectation = self.expectation(description: label)
            writer
                .writePublisher(
                    updates: { db in try db.execute(sql: "THIS IS NOT SQL") },
                    thenRead: { _, _ in XCTFail("Should not read") })
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertError(completion, label: label) { (error: DatabaseError) in
                            XCTAssertEqual(error.resultCode, .SQLITE_ERROR)
                            XCTAssertEqual(error.sql, "THIS IS NOT SQL")
                        }
                        expectation.fulfill()
                },
                    receiveValue: { _ in })
                .add(to: cancelBag)
            waitForExpectations(timeout: 1, handler: nil)
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { DatabaseQueue() }
            .runInTemporaryDirectory("DatabaseQueue") { try DatabaseQueue(path: $0) }
            .runInTemporaryDirectory("DatabasePool") { try DatabasePool(path: $0) }
    }
    
    // MARK: -
    
    func testWriteThenReadPublisherReadError() throws {
        func test(writer: DatabaseWriter, cancelBag: CancelBag, label: String) {
            let expectation = self.expectation(description: label)
            writer
                .writePublisher(
                    updates: { _ in },
                    thenRead: { db, _ in try Row.fetchAll(db, sql: "THIS IS NOT SQL") })
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertError(completion, label: label) { (error: DatabaseError) in
                            XCTAssertEqual(error.resultCode, .SQLITE_ERROR)
                            XCTAssertEqual(error.sql, "THIS IS NOT SQL")
                        }
                        expectation.fulfill()
                },
                    receiveValue: { _ in })
                .add(to: cancelBag)
            waitForExpectations(timeout: 1, handler: nil)
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { DatabaseQueue() }
            .runInTemporaryDirectory("DatabaseQueue") { try DatabaseQueue(path: $0) }
            .runInTemporaryDirectory("DatabasePool") { try DatabasePool(path: $0) }
    }
}
