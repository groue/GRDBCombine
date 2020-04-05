import GRDB
import Combine

@dynamicMemberLookup
public class DatabaseEditable<Value: MutablePersistableRecord>: ObservableObject {
	let database: DatabaseWriter
	var autoSave: Bool
	var value: Value {
		didSet {
			if autoSave {
				try? commitChanges()
			}
		}
	}
	
	public func commitChanges() throws {
		try database.write {
			try value.update($0)
		}
	}
	
	public init(database: DatabaseWriter, value: Value, autoSave: Bool = true) {
		self.database = database
		self.autoSave = autoSave
		self.value = value
	}
	
	public subscript<T>(dynamicMember keyPath: WritableKeyPath<Value, T>) -> T
	{
		get { value[keyPath: keyPath] }
		set { value[keyPath: keyPath] = newValue }
	}
}

