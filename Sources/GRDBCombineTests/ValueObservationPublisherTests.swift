import Combine
import CombineExpectations
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

class ValueObservationPublisherTests : XCTestCase {
    
    func testChangesNotifications() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write(Player.createTable)
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            let publisher = Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
            let recorder = publisher.record()
            
            try writer.writeWithoutTransaction { db in
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                
                try db.inTransaction {
                    try Player(id: 2, name: "Barbara", score: 750).insert(db)
                    try Player(id: 3, name: "Craig", score: 500).insert(db)
                    return .commit
                }
            }
            
            let elements = try wait(for: recorder.next(3), timeout: 1)
            XCTAssertEqual(elements, [0, 1, 3])
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    func testDefaultScheduler() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write(Player.createTable)
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            let expectation = self.expectation(description: "")
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .handleEvents(receiveOutput: { _ in
                    dispatchPrecondition(condition: .onQueue(.main))
                })
                .collect(2)
                .sink(
                    receiveCompletion: { completion in
                        assertNoFailure(completion)
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
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    func testFirstValueIsEmittedAsynchronously() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write(Player.createTable)
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            let expectation = self.expectation(description: "")
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
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    // MARK: - FetchOnSubscription
    
    func testFetchOnSubscriptionChangesNotifications() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write(Player.createTable)
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            let publisher = Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .fetchOnSubscription()
            let recorder = publisher.record()
            
            try writer.writeWithoutTransaction { db in
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
                
                try db.inTransaction {
                    try Player(id: 2, name: "Barbara", score: 750).insert(db)
                    try Player(id: 3, name: "Craig", score: 500).insert(db)
                    return .commit
                }
            }
            
            let elements = try wait(for: recorder.next(3), timeout: 1)
            XCTAssertEqual(elements, [0, 1, 3])
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    func testFetchOnSubscriptionDefaultScheduler() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write(Player.createTable)
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            let expectation = self.expectation(description: "")
            let testSubject = PassthroughSubject<Int, Error>()
            let testCancellable = testSubject
                .handleEvents(receiveOutput: { _ in
                    dispatchPrecondition(condition: .onQueue(.main))
                })
                .collect(2)
                .sink(
                    receiveCompletion: { completion in
                        assertNoFailure(completion)
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
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    func testFetchOnSubscriptionEmitsFirstValueSynchronously() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write(Player.createTable)
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
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
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    // MARK: - Demand
    
    private class DemandSubscriber<Input, Failure: Error>: Subscriber {
        private var subscription: Subscription?
        let subject = PassthroughSubject<Input, Failure>()
        deinit {
            subscription?.cancel()
        }
        
        func cancel() {
            subscription!.cancel()
        }
        
        func request(_ demand: Subscribers.Demand) {
            subscription!.request(demand)
        }
        
        func receive(subscription: Subscription) {
            self.subscription = subscription
        }
        
        func receive(_ input: Input) -> Subscribers.Demand {
            subject.send(input)
            return .none
        }
        
        func receive(completion: Subscribers.Completion<Failure>) {
            subject.send(completion: completion)
        }
    }
    
    func testDemandNoneReceivesNoElement() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write(Player.createTable)
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            let subscriber = DemandSubscriber<Int, Error>()
            Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .subscribe(subscriber)
            
            let expectation = self.expectation(description: "")
            expectation.isInverted = true
            let testCancellable = subscriber.subject
                .sink(
                    receiveCompletion: { _ in XCTFail("Unexpected completion") },
                    receiveValue: { _ in expectation.fulfill() })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            subscriber.cancel()
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    func testDemandOneReceivesOneElement() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write(Player.createTable)
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            let subscriber = DemandSubscriber<Int, Error>()
            Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .subscribe(subscriber)
            
            subscriber.request(.max(1))
            
            let expectation = self.expectation(description: "")
            let testCancellable = subscriber.subject.sink(
                receiveCompletion: { _ in XCTFail("Unexpected completion") },
                receiveValue: { value in
                    XCTAssertEqual(value, 0)
                    expectation.fulfill()
            })
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            subscriber.cancel()
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    func testDemandOneDoesNotReceiveTwoElements() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write(Player.createTable)
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            let subscriber = DemandSubscriber<Int, Error>()
            Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .subscribe(subscriber)
            
            subscriber.request(.max(1))
            
            let expectation = self.expectation(description: "")
            expectation.isInverted = true
            let testCancellable = subscriber.subject
                .collect(2)
                .sink(
                    receiveCompletion: { _ in XCTFail("Unexpected completion") },
                    receiveValue: { _ in expectation.fulfill() })
            
            try writer.writeWithoutTransaction { db in
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            subscriber.cancel()
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
    
    func testDemandTwoReceivesTwoElements() throws {
        func setUp<Writer: DatabaseWriter>(_ writer: Writer) throws -> Writer {
            try writer.write(Player.createTable)
            return writer
        }
        
        func test(writer: DatabaseWriter) throws {
            let subscriber = DemandSubscriber<Int, Error>()
            Player
                .observationForCount()
                .publisher(in: writer as DatabaseReader)
                .subscribe(subscriber)
            
            subscriber.request(.max(2))
            
            let expectation = self.expectation(description: "")
            let testCancellable = subscriber.subject
                .collect(2)
                .sink(
                    receiveCompletion: { _ in XCTFail("Unexpected completion") },
                    receiveValue: { values in
                        XCTAssertEqual(values, [0,1])
                        expectation.fulfill()
                })
            
            try writer.writeWithoutTransaction { db in
                try Player(id: 1, name: "Arthur", score: 1000).insert(db)
            }
            
            waitForExpectations(timeout: 1, handler: nil)
            testCancellable.cancel()
            subscriber.cancel()
        }
        
        try Test(test)
            .run { try setUp(DatabaseQueue()) }
            .runAtTemporaryDatabasePath { try setUp(DatabaseQueue(path: $0)) }
            .runAtTemporaryDatabasePath { try setUp(DatabasePool(path: $0)) }
    }
}
