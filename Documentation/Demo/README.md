Demo Application
================

<img align="right" src="https://github.com/groue/GRDBCombine/raw/master/Documentation/Demo/Screenshots/Demo1.png" width="50%">


## Models

- [AppDatabase.swift](GRDBCombineDemo/Models/AppDatabase.swift)
    
    AppDatabase defines the database for the whole application. It uses [DatabaseMigrator](https://github.com/groue/GRDB.swift/blob/master/README.md#migrations) in order to setup the database schema, and a [DatabasePool](https://github.com/groue/GRDB.swift/blob/master/README.md#database-pools) for efficient multi-threading.

- [Player.swift](GRDBCombineDemo/Models/Player.swift)
    
    Player is a [Record](https://github.com/groue/GRDB.swift/blob/master/README.md#records) type, able to read and write in the database. It conforms to the standard Codable protocol in order to gain all advantages of [Codable Records](https://github.com/groue/GRDB.swift/blob/master/README.md#codable-records).
    
    ```swift
    struct Player {
        var id: Int64? // Use Int64 for auto-incremented database ids
        var name: String
        var score: Int
    }
    ```


- [Players.swift](GRDBCombineDemo/Models/Players.swift)
    
    Players provides defines read and write operations on the players database.
    
    It exposes a [publisher](../../Sources/GRDBCombine/DatabasePublishersValue.swift) of HallOfFame, that change everytime the database is modified.
    
    ```swift
    struct HallOfFame {
        /// Total number of players
        var playerCount: Int
        
        /// The best ones
        var bestPlayers: [Player]
    }
    ```

## User Interface

- [CountViewController.swift](GRDBCombineDemo/UI/CountViewController.swift)
    
    CountViewController uses a DatabasePublisher in order to update a UILabel with the number of players

- [HallOfFameViewModel.swift](GRDBCombineDemo/UI/HallOfFameViewModel.swift)
    
    HallOfFameViewModel uses a [@DatabasePublished](../../Sources/GRDBCombine/DatabasePublished.swift) property wrapper in order to keep its content in sync with the database content, and expose it to both [HallOfFameViewController.swift](GRDBCombineDemo/UI/HallOfFameViewController.swift) and the SwiftUI [HallOfFameView.swift](GRDBCombineDemo/UI/HallOfFameView.swift).
