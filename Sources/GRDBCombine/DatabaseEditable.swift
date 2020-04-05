import GRDB
import Combine

/// An observable object that holds a `MutablePersistableRecord` and allows mutation + updating the database row
@dynamicMemberLookup
public class DatabaseEditable<Value: MutablePersistableRecord>: ObservableObject {
	let database: DatabaseWriter?
	var autoSave: Bool
	public var value: Value {
		willSet {
			objectWillChange.send()
		}
		didSet {
			if autoSave {
				try? commitChanges()
			}
		}
	}
	
	/// Call this function to manually save any changes to the record to the database
	public func commitChanges() throws {
		try database?.write {
			try value.update($0)
		}
	}
	
	/// Call this function to manually save any changes to the record to the database
	/// - parameter database: The database to save any changes to. If this is nil, changes to the value will not be saved.
	/// - parameter value: The initial value
	/// - parameter autoSave: Whether to automatically commit any changes to the database. Default = true
	public init(database: DatabaseWriter?, value: Value, autoSave: Bool = true) {
		self.database = database
		self.autoSave = autoSave
		self.value = value
	}
	
	/// Allows for directly accessing/editing variables in the stored value
	public subscript<T>(dynamicMember keyPath: WritableKeyPath<Value, T>) -> T
	{
		get { value[keyPath: keyPath] }
		set { value[keyPath: keyPath] = newValue }
	}
}

