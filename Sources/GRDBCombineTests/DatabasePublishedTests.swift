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
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(reader: DatabaseReader) throws {
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
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    func testInitializerWithoutInitialValueError() throws {
        func test(reader: DatabaseReader) throws {
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
            .run { DatabaseQueue() }
            .runAtTemporaryDatabasePath { try DatabaseQueue(path: $0) }
            .runAtTemporaryDatabasePath { try DatabasePool(path: $0) }
            .runAtTemporaryDatabasePath { try DatabasePool(path: $0).makeSnapshot() }
    }
    
    func testInitializerWithoutInitialAsPublisher() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            class Model {
                static var countPublisher: DatabasePublishers.Value<Int>!
                @DatabasePublished(countPublisher)
                var count: Result<Int, Error>
            }
            
            Model.countPublisher = Player.observationForCount().publisher(in: writer)
            let model = Model()
            
            let expectation = self.expectation(description: "")
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .collect(3)
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion)
                },
                    receiveValue: { value in
                        XCTAssertEqual(value, [0, 1, 3])
                        expectation.fulfill()
                })
            
            let observationCancellable = model
                .$count
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
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    func testInitializerWithoutInitialWillChange() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            class Model {
                static var countPublisher: DatabasePublishers.Value<Int>!
                @DatabasePublished(countPublisher)
                var count: Result<Int, Error>
            }
            
            Model.countPublisher = Player.observationForCount().publisher(in: writer)
            let model = Model()
            
            let expectation = self.expectation(description: "")
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .collect(2)
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion)
                },
                    receiveValue: { value in
                        XCTAssertEqual(value, [0, 1])
                        expectation.fulfill()
                })
            
            let observationCancellable = model
                .$count
                .objectWillChange
                .tryMap { [unowned model] in try model.count.get() } // TODO: I don't understand why we have a memory leak without this unowned capture.
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
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    func testInitializerWithInitialValue() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(reader: DatabaseReader) throws {
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
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)).makeSnapshot() }
    }
    
    func testInitializerWithInitialAsPublisher() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write { db in
                try Player.createTable(db)
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            class Model {
                static var countPublisher: DatabasePublishers.Value<Int>!
                @DatabasePublished(initialValue: 0, countPublisher)
                var count: Result<Int, Error>
            }
            
            Model.countPublisher = Player.observationForCount().publisher(in: writer)
            let model = Model()
            
            let expectation = self.expectation(description: "")
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .collect(3)
                .sink(
                    receiveCompletion: { completion in
                        XCTAssertNoFailure(completion)
                },
                    receiveValue: { value in
                        XCTAssertEqual(value, [0, 1, 3])
                        expectation.fulfill()
                })
            
            let observationCancellable = model
                .$count
                .subscribe(testSubject)
            
            try writer.write { db in
                try Player(id: 2, name: "Barbara", score: 750).insert(db)
                try Player(id: 3, name: "Craig", score: 500).insert(db)
            }
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            observationCancellable.cancel()
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
}
