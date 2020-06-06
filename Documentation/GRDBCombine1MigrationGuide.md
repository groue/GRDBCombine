Migrating From GRDBCombine 0.x to GRDBCombine 1.0
=================================================

**This guide aims at helping you upgrading your applications.**

GRDBCombine 1.0 comes with breaking changes. Those changes have the vanilla [GRDB], [GRDBCombine], and [RxGRDB], offer a consistent behavior. This greatly helps choosing or switching your preferred database API. In previous versions, the three companion libraries used to have subtle differences that were just opportunities for bugs.

1. GRDBCombine requirements have been bumped:
    
    - **Swift 5.2+** (was Swift 5.0+)
    - **Xcode 11.4+** (was Xcode 11.0+)
    - iOS 13.0+ (unchanged)
    - macOS 10.15+ (unchanged)
    - tvOS 13.0+ (unchanged)
    - watchOS 6.0+ (unchanged)
    - **GRDB 5.0+** (was GRDB 4.1+)

2. GRDBCombine 1.0 requires GRDB 5, which has changed the runtime behavior of [ValueObservation]. This directly impacts GRDBCombine publishers. Please check [Migrating From GRDB 4 to GRDB 5] for a detailed description of the changes.

3. The `fetchOnSubscription()` method of the ValueObservation subscriber has been removed. Replace it with `scheduling: .immediate` for the same effect (an initial value is notified immediately, synchronously, when the publisher is subscribed):
    
    ```swift
    // BEFORE: GRDBCombine 0.x
    let observation = ValueObservation.tracking { db in ... }
    let publisher = observation
        .publisher(in: dbQueue)
        .fetchOnSubscription()
    
    // NEW: GRDBCombine 1.0
    let observation = ValueObservation.tracking { db in ... }
    let publisher = observation
        .publisher(in: dbQueue, scheduling: .immediate)
    ```

[GRDB]: https://github.com/groue/GRDB.swift
[GRDBCombine]: https://github.com/groue/GRDBCombine
[RxGRDB]: https://github.com/RxSwiftCommunity/RxGRDB
[ValueObservation]: https://github.com/groue/GRDB.swift/blob/master/README.md#valueobservation
[Migrating From GRDB 4 to GRDB 5]: https://github.com/groue/GRDB.swift/blob/master/Documentation/GRDB5MigrationGuide.md
