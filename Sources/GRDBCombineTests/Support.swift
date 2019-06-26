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
        let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GRDBCombine", isDirectory: true)
            .appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString, isDirectory: true)
        
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        defer {
            try! FileManager.default.removeItem(at: directoryURL)
        }
        
        let databasePath = directoryURL.appendingPathComponent("db.sqlite").path
        let context = try makeContext(databasePath)
        try executeTest(label: label, context: context)
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

public func XCTAssertNoFailure<Failure>(_ completion: Subscribers.Completion<Failure>, label: String, file: StaticString = #file, line: UInt = #line) {
    if case let .failure(error) = completion {
        XCTFail("\(label): unexpected completion failure: \(error)", file: file, line: line)
    }
}

public func XCTAssertError<Failure, ExpectedFailure>(_ completion: Subscribers.Completion<Failure>, label: String, file: StaticString = #file, line: UInt = #line, test: (ExpectedFailure) -> Void) {
    if case let .failure(error) = completion, let failure = error as? ExpectedFailure {
        test(failure)
    } else {
        XCTFail("\(label): unexpected \(ExpectedFailure.self), got \(completion)", file: file, line: line)
    }
}
