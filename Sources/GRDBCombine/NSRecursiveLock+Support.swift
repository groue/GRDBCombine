import Foundation
import Dispatch

extension NSRecursiveLock {
    func synchronized<T>(_ message: @autoclosure () -> String = #function, _ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
    
//    // Verbose version which helps understanding locking bugs
//    func synchronized<T>(_ message: @autoclosure () -> String = "", _ block: () throws -> T) rethrows -> T {
//        let queueName = String(validatingUTF8: __dispatch_queue_get_label(nil))
//        print("\(queueName ?? "n/d"): \(message()) acquiring \(self)")
//        lock()
//        print("\(queueName ?? "n/d"): \(message()) acquired \(self)")
//        defer {
//            print("\(queueName ?? "n/d"): \(message()) releasing \(self)")
//            unlock()
//            print("\(queueName ?? "n/d"): \(message()) released \(self)")
//        }
//        return try block()
//    }
    
    /// Performs the side effect outside of the synchronized block. This allows
    /// avoiding deadlocks, when the side effect feedbacks.
    func synchronizedWithSideEffect(_ message: @autoclosure () -> String = #function, _ sideEffect: () throws -> (() -> Void)?) rethrows {
        try synchronized(message(), sideEffect)?()
    }
}

let noSideEffect: (() -> Void)? = nil
