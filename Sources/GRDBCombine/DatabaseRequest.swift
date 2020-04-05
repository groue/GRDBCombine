import Foundation
import Combine
import GRDB

public class DatabaseRequest<Data>: ObservableObject {
	@Published public var result: Data
	
	private var subscription: AnyCancellable?
	private let publisher: AnyPublisher<Data, Never>
	
	// Database request returning an array of records using a simple QueryInterfaceRequest
	public init<Database: DatabaseReader, DataElement: FetchableRecord>(db: Database, fetchRequest: QueryInterfaceRequest<DataElement>) where Data == [DataElement] {
		self.result = []
		self.publisher = ValueObservation
			.tracking(value: { db in
				try DataElement.fetchAll(db, fetchRequest)
			})
			.publisher(in: db)
			.replaceError(with: [])
			.eraseToAnyPublisher()
		subscribe()
	}
	
	public typealias RequestClosure = ( (_ database: Database) throws -> Data)
	
	// Database request returning an array of Records
	public init<Database: DatabaseReader, DataElement>(db: Database, request: @escaping RequestClosure) where Data == [DataElement] {
		self.result = []
		self.publisher = ValueObservation
			.tracking(value: request)
			.publisher(in: db)
			.replaceError(with: [])
			.eraseToAnyPublisher()
		subscribe()
	}
	
	// Database request returning an non-optional result, with a default value if no record/s found
	public init<Database: DatabaseReader>(db: Database, defaultValue: Data, request: @escaping RequestClosure) {
		self.result = defaultValue
		self.publisher = ValueObservation
			.tracking(value: request)
			.publisher(in: db)
			.replaceError(with: defaultValue)
			.eraseToAnyPublisher()
		subscribe()
	}
	
	// Database request returning an optional Record
	public init<Database: DatabaseReader, DataElement>(db: Database, request: @escaping RequestClosure) where Data == Optional<DataElement> {
		self.result = nil
		self.publisher = ValueObservation
			.tracking(value: request)
			.publisher(in: db)
			.replaceError(with: nil)
			.eraseToAnyPublisher()
		subscribe()
	}
	
	func subscribe() {
		subscription = publisher.sink { [unowned self] result in
			self.result = result
		}
	}
}

