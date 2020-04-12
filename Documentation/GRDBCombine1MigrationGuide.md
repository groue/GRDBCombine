Migrating From GRDBCombine 0.x to GRDBCombine 1.0
=================================================

**This guide aims at helping you upgrading your applications.**

1. GRDBCombine 1.0 requires GRDB 5, which comes with changes in the runtime behavior of [ValueObservation], and directly impacts its derived GRDBCombine publisher. So please check [Migrating From GRDB 4 to GRDB 5] first.

2. GRDBCombine requirements have been bumped:
    
    - **Swift 5.2+** (was Swift 5.0+)
    - **Xcode 11.4+** (was Xcode 11.0+)
    - iOS 13.0+ (unchanged)
    - macOS 10.15+ (unchanged)
    - tvOS 13.0+ (unchanged)
    - watchOS 6.0+ (unchanged)
    

3. The `fetchOnSubscription()` method of the ValueObservation subscriber has been removed. Replace it with `scheduling(.immediate)` for the same effect (an initial value is notified immediately, synchronously, when the publisher is subscribed):
    
    ```swift
    // BEFORE: GRDBCombine 0.x
    let observation = ValueObservation.tracking { db in ... }
    let publisher = observation
        .publisher(in: dbQueue)
        .fetchOnSubscription()
    
    // NEW: GRDBCombine 1.0
    let observation = ValueObservation.tracking { db in ... }
    let publisher = observation
        .publisher(in: dbQueue)
        .scheduling(.immediate)
    ```

[ValueObservation]: https://github.com/groue/GRDB.swift/blob/GRDB5/README.md#valueobservation
[Migrating From GRDB 4 to GRDB 5]: https://github.com/groue/GRDB.swift/blob/GRDB5/Documentation/GRDB5MigrationGuide.md