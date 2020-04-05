import Foundation
import Combine
import GRDB

/// An observable object that observes a database request and updates its `result` value with any changes
public class DatabaseRequest<Data>: ObservableObject {
	/// The result of the request. This is updated automatically with any changes.
	public var result: Data {
		willSet {
			objectWillChange.send()
		}
	}
	
	private var subscription: AnyCancellable?
	private let publisher: AnyPublisher<Data, Never>
	
	/// Database request returning an array of records using a simple QueryInterfaceRequest
	public init<Database: DatabaseReader, DataElement: FetchableRecord>(db: Database, fetchRequest: Request<DataElement>) where Data == [DataElement] {
		self.result = []
		self.publisher = ValueObservation
			.tracking({ db in
				try DataElement.fetchAll(db, fetchRequest)
			})
			.publisher(in: db)
			.replaceError(with: [])
			.eraseToAnyPublisher()
		subscribe()
	}
	
	public typealias RequestClosure = ( (_ database: Database) throws -> Data)
	
	/// Database request returning an array of Records
	public init<Database: DatabaseReader, DataElement>(db: Database, request: @escaping RequestClosure) where Data == [DataElement] {
		self.result = []
		self.publisher = ValueObservation
			.tracking(request)
			.publisher(in: db)
			.replaceError(with: [])
			.eraseToAnyPublisher()
		subscribe()
	}
	
	/// Database request returning an non-optional result, with a default value if no record/s found
	public init<Database: DatabaseReader>(db: Database, defaultValue: Data, request: @escaping RequestClosure) {
		self.result = defaultValue
		self.publisher = ValueObservation
			.tracking(request)
			.publisher(in: db)
			.replaceError(with: defaultValue)
			.eraseToAnyPublisher()
		subscribe()
	}
	
	/// Database request returning an optional Record
	public init<Database: DatabaseReader, DataElement>(db: Database, request: @escaping RequestClosure) where Data == Optional<DataElement> {
		self.result = nil
		self.publisher = ValueObservation
			.tracking(request)
			.publisher(in: db)
			.replaceError(with: nil)
			.eraseToAnyPublisher()
		subscribe()
	}
	
	/// Fake database request returning placeholder data (useful for testing / working on UI)
	public static func placeholder(data: Data) -> DatabaseRequest<Data> {
		DatabaseRequest(placeholderData: data)
	}
	
	private init(placeholderData: Data) {
		self.result = placeholderData
		self.publisher = Just(placeholderData)
			.eraseToAnyPublisher()
		subscribe()
	}
	
	private func subscribe() {
		subscription = publisher.sink { [weak self] result in
			self?.result = result
		}
	}
}

