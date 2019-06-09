import GRDB

// MARK: - Count

extension FetchRequest {
    public var observeCount: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Passthrough<Int>>> {
        return ValueObservation.trackingCount(self)
    }
}

extension TableRecord {
    public static var observeCount: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Passthrough<Int>>> {
        return all().observeCount
    }
}

// MARK: - Row

extension FetchRequest where RowDecoder == Row {
    public var observeAll: ValueObservation<RowsReducer> {
        return ValueObservation.trackingAll(self)
    }
    
    public var observeOne: ValueObservation<RowReducer> {
        return ValueObservation.trackingOne(self)
    }
}

// MARK: - FetchableRecord

extension FetchRequest where RowDecoder: FetchableRecord {
    public var observeAll: ValueObservation<FetchableRecordsReducer<RowDecoder>> {
        return ValueObservation.trackingAll(self)
    }
    
    public var observeOne: ValueObservation<FetchableRecordReducer<RowDecoder>> {
        return ValueObservation.trackingOne(self)
    }
}

extension TableRecord where Self: FetchableRecord {
    public static var observeAll: ValueObservation<FetchableRecordsReducer<Self>> {
        return all().observeAll
    }
    
    public static var observeOne: ValueObservation<FetchableRecordReducer<Self>> {
        return limit(1).observeOne
    }
}

// MARK: - DatabaseValueConvertible

extension FetchRequest where RowDecoder: DatabaseValueConvertible {
    public var observeAll: ValueObservation<DatabaseValuesReducer<RowDecoder>> {
        return ValueObservation.trackingAll(self)
    }
    
    public var observeOne: ValueObservation<DatabaseValueReducer<RowDecoder>> {
        return ValueObservation.trackingOne(self)
    }
}

extension FetchRequest where RowDecoder: _OptionalProtocol, RowDecoder._Wrapped: DatabaseValueConvertible {
    public var observeAll: ValueObservation<OptionalDatabaseValuesReducer<RowDecoder._Wrapped>> {
        return ValueObservation.trackingAll(self)
    }
}
