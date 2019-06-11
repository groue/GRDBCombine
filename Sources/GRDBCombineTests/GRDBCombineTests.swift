import XCTest
import GRDB
import GRDBCombine

class GRDBCombineTests: XCTest {
    func test() throws {
        struct Player: Codable, FetchableRecord, PersistableRecord {
            var id: Int64
            var name: String
        }
        let dbQueue = DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "player") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text)
            }
        }
        let players = Player.observationForAll()
        let publisher = DatabasePublishers.Value(players, in: dbQueue)
        let published = DatabasePublished(publisher)
        let players: [Player] = try published.value.get()
    }
    func testFailure() {
        XCTAssert(false, "failure")
    }
}
