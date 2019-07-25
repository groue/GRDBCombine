import Combine
import Foundation
import XCTest

final class Test<Context> {
    // Raise the repeatCount in order to help spotting flaky tests.
    private let repeatCount = 1
    private let test: (Context, String) throws -> ()
    
    init(_ test: @escaping (Context, String) throws -> ()) {
        self.test = test
    }
    
    @discardableResult
    func run(_ label: String = "", makeContext: () throws -> Context) throws -> Self {
        for _ in 1...repeatCount {
            try test(makeContext(), label)
        }
        return self
    }
    
    @discardableResult
    func runInTemporaryDirectory(_ label: String = "", makeContext: (_ path: String) throws -> Context) throws -> Self {
        for _ in 1...repeatCount {
            let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("GRDBCombine", isDirectory: true)
                .appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString, isDirectory: true)
            
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            defer {
                try! FileManager.default.removeItem(at: directoryURL)
            }
            
            let databasePath = directoryURL.appendingPathComponent("db.sqlite").path
            do {
                let context = try makeContext(databasePath)
                try test(context, label)
            }
        }
        return self
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
