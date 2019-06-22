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
        try Test(testReadPublisher)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
            // TODO: restore this flaky test
            // .runInTemporaryDirectory("DatabaseSnapshot") { try prepare(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    func testReadPublisher(reader: DatabaseReader, cancelBag: CancelBag, label: String) {
        let expectation = self.expectation(description: label)
        reader
            .readPublisher { db in
                try Player.fetchCount(db)
            }
            .sink(
                receiveCompletion: { completion in
                    XCTAssertNoFailure(completion)
                    expectation.fulfill()
            },
                receiveValue: { value in
                    XCTAssertEqual(value, 1)
            })
            .add(to: cancelBag)
        waitForExpectations(timeout: 1, handler: nil)
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
        try Test(testReadPublisherDefaultScheduler)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
            // TODO: restore this flaky test
            // .runInTemporaryDirectory("DatabaseSnapshot") { try prepare(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    func testReadPublisherDefaultScheduler(reader: DatabaseReader, cancelBag: CancelBag, label: String) {
        let expectation = self.expectation(description: label)
        reader
            .readPublisher { db in
                try Player.fetchCount(db)
            }
            .sink(
                receiveCompletion: { completion in
                    XCTAssertNoFailure(completion)
                    dispatchPrecondition(condition: .onQueue(.main))
                    expectation.fulfill()
            },
                receiveValue: { _ in
                    dispatchPrecondition(condition: .onQueue(.main))
            })
            .add(to: cancelBag)
        waitForExpectations(timeout: 1, handler: nil)
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
        try Test(testReadPublisherCustomScheduler)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
            .runInTemporaryDirectory("DatabaseSnapshot") { try prepare(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    func testReadPublisherCustomScheduler(reader: DatabaseReader, cancelBag: CancelBag, label: String) {
        let queue = DispatchQueue(label: "test")
        let expectation = self.expectation(description: label)
        reader
            .readPublisher(receiveOn: queue) { db in
                try Player.fetchCount(db)
            }
            .sink(
                receiveCompletion: { completion in
                    XCTAssertNoFailure(completion)
                    dispatchPrecondition(condition: .onQueue(queue))
                    expectation.fulfill()
            },
                receiveValue: { _ in
                    dispatchPrecondition(condition: .onQueue(queue))
            })
            .add(to: cancelBag)
        waitForExpectations(timeout: 1, handler: nil)
    }
    
    // MARK: -
    
    func testReadPublisherIsReadonly() throws {
        try Test(testReadPublisherIsReadonly)
            .run("InMemoryDatabaseQueue") { DatabaseQueue() }
            .runInTemporaryDirectory("DatabaseQueue") { try DatabaseQueue(path: $0) }
            .runInTemporaryDirectory("DatabasePool") { try DatabasePool(path: $0) }
            .runInTemporaryDirectory("DatabaseSnapshot") { try DatabasePool(path: $0).makeSnapshot() }
    }
    
    func testReadPublisherIsReadonly(reader: DatabaseReader, cancelBag: CancelBag, label: String) throws {
        let expectation = self.expectation(description: label)
        reader
            .readPublisher { db in
                try Player.createTable(db)
            }
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        XCTFail("Expected error")
                    case let .failure(error):
                        if let dbError = error as? DatabaseError {
                            XCTAssertEqual(dbError.resultCode, .SQLITE_READONLY)
                        } else {
                            XCTFail("Unexpected error: \(error)")
                        }
                    }
                    expectation.fulfill()
            },
                receiveValue: { _ in })
            .add(to: cancelBag)
        waitForExpectations(timeout: 1, handler: nil)
    }
}
