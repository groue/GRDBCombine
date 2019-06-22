import Combine
import Foundation
import XCTest

final class Test<Context> {
    private let test: (Context, CancelBag, String) throws -> ()
    
    init(_ test: @escaping (Context, CancelBag, String) throws -> ()) {
        self.test = test
    }
    
    @discardableResult
    func run(_ label: String = "", makeContext: () throws -> Context) throws -> Self {
        try executeTest(label: label, context: makeContext())
        return self
    }

    @discardableResult
    func runInTemporaryDirectory(_ label: String = "", makeContext: (_ path: String) throws -> Context) throws -> Self {
        // Create temp directory
        let fm = FileManager.default
        let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RxGRDBTests", isDirectory: true)
            .appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString, isDirectory: true)
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        
        do {
            // Run test inside temp directory
            let databasePath = directoryURL.appendingPathComponent("db.sqlite").path
            let context = try makeContext(databasePath)
            try executeTest(label: label, context: context)
        }
        
        // Destroy temp directory
        try! FileManager.default.removeItem(at: directoryURL)
        return self
    }
    
    private func executeTest(label: String, context: Context) throws {
        let bag = CancelBag()
        defer {
            bag.cancel()
        }
        try test(context, bag, label)
    }
}

final class CancelBag: Cancellable {
    fileprivate var cancellables: [AnyCancellable] = []
    
    func cancel() {
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables = []
    }
    
    deinit {
        cancel()
    }
}

extension Cancellable {
    func add(to bag: CancelBag) {
        bag.cancellables.append(AnyCancellable(self))
    }
}

public func XCTAssertNoFailure<Failure>(_ completion: Subscribers.Completion<Failure>, file: StaticString = #file, line: UInt = #line) {
    if case let .failure(error) = completion {
        XCTFail("Unexpected completion failure: \(error)", file: file, line: line)
    }
}
