import GRDB

// MARK: - Count

extension FetchRequest {
    // Player.filter(score > 1000).count
    public var count: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Passthrough<Int>>> {
        return ValueObservation.trackingCount(self)
    }
}

extension TableRecord {
    // Player.count
    public static var count: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Passthrough<Int>>> {
        return all().count
    }
}

// MARK: - Rows

extension FetchRequest where RowDecoder == Row {
    // SQLRequest<Row>(sql: "SELECT * FROM players").all
    public var all: ValueObservation<RowsReducer> {
        return ValueObservation.trackingAll(self)
    }
    
    // SQLRequest<Row>(sql: "SELECT * FROM players WHERE id = 1").first
    public var first: ValueObservation<RowReducer> {
        return ValueObservation.trackingOne(self)
    }
}

// MARK: - Records

extension FetchRequest where RowDecoder: FetchableRecord {
    // Player.filter(score > 1000).all
    // Player.all().all -- TODO: this is very bad
    public var all: ValueObservation<FetchableRecordsReducer<RowDecoder>> {
        return ValueObservation.trackingAll(self)
    }
    
    // Player.filter(name == "Arthur").first
    // Player.filter(key: 1).first -- TODO: this isn't good
    public var first: ValueObservation<FetchableRecordReducer<RowDecoder>> {
        return ValueObservation.trackingOne(self)
    }
}

extension TableRecord where Self: FetchableRecord {
    // Player.all
    public static var all: ValueObservation<FetchableRecordsReducer<Self>> {
        return all().all
    }
    
    // Player.first
    public static var first: ValueObservation<FetchableRecordReducer<Self>> {
        // TODO: check that limit(1) has no impact on requests like filter(key:)
        return limit(1).first
    }
}

// MARK: - Values

extension FetchRequest where RowDecoder: DatabaseValueConvertible {
    // Player.select(name, as: String.self).all
    public var all: ValueObservation<DatabaseValuesReducer<RowDecoder>> {
        return ValueObservation.trackingAll(self)
    }
    
    // Player.filter(key: 1).select(name, as: String.self).first
    public var first: ValueObservation<DatabaseValueReducer<RowDecoder>> {
        return ValueObservation.trackingOne(self)
    }
}

extension FetchRequest where RowDecoder: _OptionalProtocol, RowDecoder._Wrapped: DatabaseValueConvertible {
    // TODO: add support for trackingOne as well
    
    // Player.select(email, as: Optional<String>.self).all
    public var all: ValueObservation<OptionalDatabaseValuesReducer<RowDecoder._Wrapped>> {
        return ValueObservation.trackingAll(self)
    }
}
