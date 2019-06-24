import Combine
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

class DatabasePublishedTests : XCTestCase {
    
    func testInitializerWithoutInitialValueSuccess() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(reader: DatabaseReader, cancelBag: CancelBag, label: String) throws {
            class Model {
                static var countPublisher: DatabasePublishers.Value<Int>!
                @DatabasePublished(countPublisher)
                var count: Result<Int, Error>
            }
            
            Model.countPublisher = Player.observationForCount().publisher(in: reader)
            let model = Model()
            try XCTAssertEqual(model.count.get(), 1)
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
            .runInTemporaryDirectory("DatabaseSnapshot") { try prepare(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    func testInitializerWithoutInitialValueError() throws {
        func test(reader: DatabaseReader, cancelBag: CancelBag, label: String) throws {
            class Model {
                static var countPublisher: DatabasePublishers.Value<Int>!
                @DatabasePublished(countPublisher)
                var count: Result<Int, Error>
            }
            
            Model.countPublisher = Player.observationForCount().publisher(in: reader)
            let model = Model()
            do {
                _ = try model.count.get()
                XCTFail("Expected error")
            } catch {
                if let dbError = error as? DatabaseError {
                    XCTAssertEqual(dbError.resultCode, .SQLITE_ERROR)
                    XCTAssertEqual(dbError.message, "no such table: player")
                } else {
                    XCTFail("Expected DatabaseError")
                }
            }
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { DatabaseQueue() }
            .runInTemporaryDirectory("DatabaseQueue") { try DatabaseQueue(path: $0) }
            .runInTemporaryDirectory("DatabasePool") { try DatabasePool(path: $0) }
            .runInTemporaryDirectory("DatabaseSnapshot") { try DatabasePool(path: $0).makeSnapshot() }
    }

    func testInitializerWithInitialValue() throws {
        func prepare<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(reader: DatabaseReader, cancelBag: CancelBag, label: String) throws {
            class Model {
                static var countPublisher: DatabasePublishers.Value<Int>!
                @DatabasePublished(initialValue: 0, countPublisher)
                var count: Result<Int, Error>
            }
            
            Model.countPublisher = Player.observationForCount().publisher(in: reader)
            let model = Model()
            try XCTAssertEqual(model.count.get(), 0)
        }
        
        try Test(test)
            .run("InMemoryDatabaseQueue") { try prepare(DatabaseQueue()) }
            .runInTemporaryDirectory("DatabaseQueue") { try prepare(DatabaseQueue(path: $0)) }
            .runInTemporaryDirectory("DatabasePool") { try prepare(DatabasePool(path: $0)) }
            .runInTemporaryDirectory("DatabaseSnapshot") { try prepare(DatabasePool(path: $0)).makeSnapshot() }
    }
}
