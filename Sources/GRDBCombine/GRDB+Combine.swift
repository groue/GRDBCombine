import GRDB

// MARK: - Count

extension FetchRequest {
    public func count(in reader: DatabaseReader) -> DatabasePublishers.Value<ValueReducers.RemoveDuplicates<ValueReducers.Passthrough<Int>>> {
        return DatabasePublishers.Value(ValueObservation.trackingCount(self), in: reader)
    }
    
    @available(*, deprecated)
    public var observeCount: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Passthrough<Int>>> {
        return ValueObservation.trackingCount(self)
    }
}

extension TableRecord {
    public static func count(in reader: DatabaseReader) -> DatabasePublishers.Value<ValueReducers.RemoveDuplicates<ValueReducers.Passthrough<Int>>> {
        return all().count(in: reader)
    }
    
    @available(*, deprecated)
    public static var observeCount: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Passthrough<Int>>> {
        return all().observeCount
    }
}

// MARK: - Row

extension FetchRequest where RowDecoder == Row {
    public func all(in reader: DatabaseReader) -> DatabasePublishers.Value<RowsReducer> {
        return DatabasePublishers.Value(ValueObservation.trackingAll(self), in: reader)
    }
    
    public func first(in reader: DatabaseReader) -> DatabasePublishers.Value<RowReducer> {
        return DatabasePublishers.Value(ValueObservation.trackingOne(self), in: reader)
    }
    
    @available(*, deprecated)
    public var observeAll: ValueObservation<RowsReducer> {
        return ValueObservation.trackingAll(self)
    }
    
    @available(*, deprecated)
    public var observeOne: ValueObservation<RowReducer> {
        return ValueObservation.trackingOne(self)
    }
}

// MARK: - FetchableRecord

extension FetchRequest where RowDecoder: FetchableRecord {
    public func all(in reader: DatabaseReader) -> DatabasePublishers.Value<FetchableRecordsReducer<RowDecoder>> {
        return DatabasePublishers.Value(ValueObservation.trackingAll(self), in: reader)
    }
    
    public func first(in reader: DatabaseReader) -> DatabasePublishers.Value<FetchableRecordReducer<RowDecoder>> {
        return DatabasePublishers.Value(ValueObservation.trackingOne(self), in: reader)
    }
    
    @available(*, deprecated)
    public var observeAll: ValueObservation<FetchableRecordsReducer<RowDecoder>> {
        return ValueObservation.trackingAll(self)
    }
    
    @available(*, deprecated)
    public var observeOne: ValueObservation<FetchableRecordReducer<RowDecoder>> {
        return ValueObservation.trackingOne(self)
    }
}

extension TableRecord where Self: FetchableRecord {
    public static func all(in reader: DatabaseReader) -> DatabasePublishers.Value<FetchableRecordsReducer<Self>> {
        return all().all(in: reader)
    }
    
    public static func first(in reader: DatabaseReader) -> DatabasePublishers.Value<FetchableRecordReducer<Self>> {
        return limit(1).first(in: reader)
    }
    
    @available(*, deprecated)
    public static var observeAll: ValueObservation<FetchableRecordsReducer<Self>> {
        return all().observeAll
    }
    
    @available(*, deprecated)
    public static var observeOne: ValueObservation<FetchableRecordReducer<Self>> {
        return limit(1).observeOne
    }
}

// MARK: - DatabaseValueConvertible

extension FetchRequest where RowDecoder: DatabaseValueConvertible {
    public func all(in reader: DatabaseReader) -> DatabasePublishers.Value<DatabaseValuesReducer<RowDecoder>> {
        return DatabasePublishers.Value(ValueObservation.trackingAll(self), in: reader)
    }
    
    public func first(in reader: DatabaseReader) -> DatabasePublishers.Value<DatabaseValueReducer<RowDecoder>> {
        return DatabasePublishers.Value(ValueObservation.trackingOne(self), in: reader)
    }
    
    @available(*, deprecated)
    public var observeAll: ValueObservation<DatabaseValuesReducer<RowDecoder>> {
        return ValueObservation.trackingAll(self)
    }
    
    @available(*, deprecated)
    public var observeOne: ValueObservation<DatabaseValueReducer<RowDecoder>> {
        return ValueObservation.trackingOne(self)
    }
}

extension FetchRequest where RowDecoder: _OptionalProtocol, RowDecoder._Wrapped: DatabaseValueConvertible {
    public func all(in reader: DatabaseReader) -> DatabasePublishers.Value<OptionalDatabaseValuesReducer<RowDecoder._Wrapped>> {
        return DatabasePublishers.Value(ValueObservation.trackingAll(self), in: reader)
    }
    
    @available(*, deprecated)
    public var observeAll: ValueObservation<OptionalDatabaseValuesReducer<RowDecoder._Wrapped>> {
        return ValueObservation.trackingAll(self)
    }
}
