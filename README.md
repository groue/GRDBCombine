GRDBCombine
===========

### A set of extensions for [SQLite], [GRDB.swift], and [Combine]

---

**Latest release**: July 26, 2019 • version 0.3.0 • [Release Notes]

**Requirements**: iOS 13.0+ / macOS 10.15+ / watchOS 6.0+ &bull; Swift 5.1+ / Xcode 11.0 beta 4

:construction: **Don't use in production** - this is beta software.

:mega: **Please provide feedback** - this is how experimental software turns into robust and reliable solutions that help us doing our everyday job. Don't be shy! Open [issues](https://github.com/groue/GRDBCombine/issues) and ask questions, contact [@groue](http://twitter.com/groue).

---

## Usage

To connect to the database, please refer to [GRDB](https://github.com/groue/GRDB.swift), the database library that supports GRDBCombine.

<details open>
  <summary>Observe database changes</summary>

```swift
// Observe the results of a request
let request = Player.all()
let publisher = request.observationForAll().publisher(in: dbQueue)
let cancellable = publisher.sink(
    receiveCompletion: { completion in ... },
    receiveValue: { (players: [Player]) in
        print("Fresh players: \(players)")
    })

// Observe the first result of a request
let request = Player.filter(key: 1)
let publisher = request.observationForFirst().publisher(in: dbQueue)
let cancellable = publisher.sink(
    receiveCompletion: { completion in ... },
    receiveValue: { (player: Player?) in
        print("Fresh player: \(player)")
    })

// Observe raw SQL requests
let request: SQLRequest<Int> = "SELECT MAX(score) FROM player"
let publisher = request.observationForFirst().publisher(in: dbQueue)
let cancellable = publisher.sink(
    receiveCompletion: { completion in ... },
    receiveValue: { (score: Int?) in
        print("Fresh maximum score: \(score)")
    })
```

</details>

<details>
  <summary>Define auto-updating properties</summary>

```swift
class MyModel {
    static let playersPublisher = Player.observationForAll().publisher(in: dbQueue)
    
    @DatabasePublished(playersPublisher)
    var players: Result<[Players], Error>
}
```

</details>

<details>
  <summary>Asynchronously write in the database</summary>

```swift
// AnyPublisher<Void, Error>
let write = dbQueue.writePublisher { db in
    try Player(...).insert(db)
}

// AnyPublisher<Int, Error>
let newPlayerCount = dbQueue.writePublisher { db -> Int in
    try Player(...).insert(db)
    return try Player.fetchCount(db)
}
```

</details>

<details>
  <summary>Asynchronously read from the database</summary>

```swift
// AnyPublisher<[Player], Error>
let players = dbQueue.readPublisher { db in
    try Player.fetchAll(db)
}
```

</details>

Documentation
=============

- [Reference]
- [Installation]
- [Demo Application]
- [Asynchronous Database Access]
- [Database Observation]
- [@DatabasePublished]

## Installation

The [Swift Package Manager] automates the distribution of Swift code. To use GRDBCombine with SPM, add a dependency to your `Package.swift` file:

```swift
let package = Package(
    dependencies: [
        .package(url: "https://github.com/groue/GRDBCombine.git", .exact("0.3.0"))
    ]
)
```


# Asynchronous Database Access

GRDBCombine provide publishers that perform asynchronous database accesses.

- [`readPublisher(receiveOn:value:)`]
- [`writePublisher(receiveOn:updates:)`]
- [`writePublisher(receiveOn:updates:thenRead:)`]


#### `DatabaseReader.readPublisher(receiveOn:value:)`

This methods returns a publisher that completes after database values have been asynchronously fetched.

```swift
// AnyPublisher<[Player], Error>
let players = dbQueue.readPublisher { db in
    try Player.fetchAll(db)
}
```

The fetched value is published on the main queue, unless you provide a specific scheduler to the `receiveOn` argument.

A new database access starts each time this publisher is subscribed to.


#### `DatabaseWriter.writePublisher(receiveOn:updates:)`

This method returns a publisher that completes after database updates have been succesfully executed inside a database transaction.

```swift
// AnyPublisher<Void, Error>
let write = dbQueue.writePublisher { db in
    try Player(...).insert(db)
}

// AnyPublisher<Int, Error>
let newPlayerCount = dbQueue.writePublisher { db -> Int in
    try Player(...).insert(db)
    return try Player.fetchCount(db)
}
```

The publisher completes on the main queue, unless you provide a specific [scheduler] to the `receiveOn` argument.

A new database access starts each time this publisher is subscribed to.

When you use a [database pool], and your app executes some database updates followed by some slow fetches, you may profit from optimized scheduling with [`writePublisher(receiveOn:updates:thenRead:)`]. See below.


#### `DatabaseWriter.writePublisher(receiveOn:updates:thenRead:)`

This method returns a publisher that completes after database updates have been succesfully executed inside a database transaction, and values have been subsequently fetched:

```swift
// AnyPublisher<Int, Error>
let newPlayerCount = dbQueue.writePublisher(
    updates: { db in try Player(...).insert(db) }
    thenRead: { db, _ in try Player.fetchCount(db) })
}
```

It publishes exactly the same values as [`writePublisher(receiveOn:updates:)`]:

```swift
// AnyPublisher<Int, Error>
let newPlayerCount = dbQueue.writePublisher { db -> Int in
    try Player(...).insert(db)
    return try Player.fetchCount(db)
}
```

The difference is that the last fetches are performed in the `thenRead` function. This function accepts two arguments: a readonly database connection, and the result of the `updates` function. This allows you to pass information from a function to the other (it is ignored in the sample code above).

When you use a [database pool], this method applies a scheduling optimization: the `thenRead` function sees the database in the state left by the `updates` function, and yet does not block any concurrent writes. See [Advanced DatabasePool](https://github.com/groue/GRDB.swift/tree/GRDB-4.1#advanced-databasepool) for more information.

When you use a [database queue], the results are guaranteed to be identical, but no scheduling optimization is applied.

The publisher completes on the main queue, unless you provide a specific [scheduler] to the `receiveOn` argument.

A new database access starts each time this publisher is subscribed to.


# Database Observation

**GRDBCombine notifies changes that have been committed in the database.** No insertion, update, or deletion in tracked tables is missed. This includes indirect changes triggered by [foreign keys](https://www.sqlite.org/foreignkeys.html#fk_actions) or [SQL triggers](https://www.sqlite.org/lang_createtrigger.html).

To function correctly, GRDBCombine requires that a unique [database connection] is kept open during the whole duration of the observation.

> :point_up: **Note**: some special changes are not notified: changes to SQLite system tables (such as `sqlite_master`), and changes to [`WITHOUT ROWID`](https://www.sqlite.org/withoutrowid.html) tables. See [Data Change Notification Callbacks](https://www.sqlite.org/c3ref/update_hook.html) for more information.

To define which part of the database should be observed, you provide database requests. Requests can be expressed with GRDB's [query interface], as in `Player.all()`, or with SQL, as in `SELECT * FROM player`. Both would observe the full "player" database table. Observed requests can involve several database tables, and generally be as complex as you need them to be.

GRDBCombine publishers are based on GRDB's [ValueObservation] and [DatabaseRegionObservation]. If your application needs change notifications that are not built in GRDBCombine, check the general [Database Changes Observation] chapter.

- [`ValueObservation.publisher(in:)`]
- [`DatabaseRegionObservation.publisher(in:)`]


#### `ValueObservation.publisher(in:)`

GRDB's [ValueObservation] tracks changes in the results of database requests, and notifies fresh values whenever the database changes. GRDBCombine can build Combine publishers from it:

```swift
let request = Player.all()

// AnyPublisher<Int, Error>
let publisher = request.observationForCount().publisher(in: dbQueue)

// AnyPublisher<Player?, Error>
let publisher = request.observationForFirst().publisher(in: dbQueue)

// AnyPublisher<[Player], Error>
let publisher = request.observationForAll().publisher(in: dbQueue)
```

This publisher always publishes an initial value, and waits for database changes before publishing updated values. It only completes when a database error happens.

All values are published on the main queue. Future GRDBCombine versions may lift this limitation.

All values are published asynchronously, unless you modify the publisher with the `fetchOnSubscription()` method. In this case, the publisher synchronously fetches its initial value right on subscription. Subscription must then happen from the main queue, or you will get a fatal error:

```swift
let request = Player.all()
let publisher = request.observationForAll().publisher(in: dbQueue)
let cancellable = publisher.fetchOnSubscription().sink(
    receiveCompletion: { completion in ... },
    receiveValue: { (players: [Player]) in
        print("Fresh players: \(players)")
    })
// <- here "Fresh players" has been printed.
```

:warning: DO NOT compose ValueObservation publishers together with the [combineLatest](https://developer.apple.com/documentation/combine/publisher/3333677-combinelatest) operator: you would lose all guarantees of [data consistency](https://en.wikipedia.org/wiki/Consistency_(database_systems)).

```swift
// CAUTION: DATA CONSISTENCY NOT GUARANTEED
let team = Team.filter(key: 1).observationForFirst().publisher(in: dbQueue)
let players = Player.filter(teamId: 1).observationForAll().publisher(in: dbQueue)
let publisher = team.combineLatest(players)
```

Instead, compose requests or value observations together **before** building a **single** publisher:

```swift
// Data consistency guaranteed by combining value observations
let team = Team.filter(key: 1).observationForFirst()
let players = Player.filter(teamId: 1).observationForAll()
let observation = ValueObservation.combine(team, players)
// AnyPublisher<(Team?, [Player]), Error>
let publisher = observation.publisher(in: dbQueue)

// Data consistency guaranteed by associations
struct TeamInfo: FetchableRecord, Decodable {
    var team: Team
    var players: [Player]
}
let request = Team
    .filter(key: 1)
    .including(all: Team.players)
    .asRequest(of: TeamInfo.self)
// AnyPublisher<TeamInfo?, Error>
let publisher = request.observationForFirst().publisher(in: dbQueue)
```

See [ValueObservation] and [Associations] for more information.


#### `DatabaseRegionObservation.publisher(in:)`

TODO: test this publisher, and document


# @DatabasePublished

**DatabasePublished is a property wrapper** that automatically updates the value of a property as database content changes.

You declare a @DatabasePublished property with a database publisher returned from [`ValueObservation.publisher(in:)`]:

```swift
class MyModel {
    static let playersPublisher = Player.observationForAll().publisher(in: dbQueue)
    
    @DatabasePublished(playersPublisher)
    var players: Result<[Players], Error>
}

let model = MyModel()
try model.players.get() // [Player]
model.$players          // Publisher of output [Player], failure Error
```

By default, the initial value of the property is immediately fetched from the database. This blocks your main queue until the database access completes.

You can opt in for asynchronous fetching of this first database value by providing an explicit initial value to the property:

```swift
class MyModel {
    // The initialValue argument triggers asynchronous fetching
    @DatabasePublished(initialValue: [], playersPublisher)
    var players: Result<[Players], Error>
}

let model = MyModel()
// Empty array until the initial fetch is performed
try model.players.get()
```

@DatabasePublished properties track their changes in the database during their whole life time. It is not advised to use them in a value type such as a struct.

@DatabasePublished properties must be used from the main queue. It is a programmer error to create or access those properties from any other queue. Future GRDBCombine versions may soothe this limitation.

The DatabasePublished property wrapper conforms to the SwiftUI [BindableObject] protocol.


[@DatabasePublished]: #DatabasePublished
[Associations]: https://github.com/groue/GRDB.swift/blob/master/Documentation/AssociationsBasics.md
[Asynchronous Database Access]: #asynchronous-database-access
[BindableObject]: https://developer.apple.com/documentation/swiftui/bindableobject
[Combine]: https://developer.apple.com/documentation/combine
[Database Changes Observation]: https://github.com/groue/GRDB.swift/blob/master/README.md#database-changes-observation
[Database Observation]: #database-observation
[DatabaseRegionObservation]: https://github.com/groue/GRDB.swift/blob/master/README.md#databaseregionobservation
[Demo Application]: Documentation/Demo/README.md
[GRDB.swift]: https://github.com/groue/GRDB.swift
[Installation]: #installation
[Reference]: https://groue.github.io/GRDBCombine/docs/0.3/index.html
[Release Notes]: CHANGELOG.md
[SQLite]: http://sqlite.org
[Swift Package Manager]: https://swift.org/package-manager/
[ValueObservation]: https://github.com/groue/GRDB.swift/blob/master/README.md#valueobservation
[`DatabaseRegionObservation.publisher(in:)`]: #databaseregionobservationpublisherin
[`ValueObservation.publisher(in:)`]: #valueobservationpublisherin
[`readPublisher(receiveOn:value:)`]: #databasereaderreadpublisherreceiveonvalue
[`writePublisher(receiveOn:updates:)`]: #databasewriterwritepublisherreceiveonupdates
[`writePublisher(receiveOn:updates:thenRead:)`]: #databasewriterwritepublisherreceiveonupdatesthenread
[database connection]: https://github.com/groue/GRDB.swift/blob/master/README.md#database-connections
[database pool]: https://github.com/groue/GRDB.swift/blob/master/README.md#database-pools
[database queue]: https://github.com/groue/GRDB.swift/blob/master/README.md#database-queues
[query interface]: https://github.com/groue/GRDB.swift/blob/master/README.md#requests
[scheduler]: https://developer.apple.com/documentation/combine/scheduler
