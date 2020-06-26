import Combine
import Foundation

/// A publisher that delivers values to its downstream subscriber on a
/// specific scheduler.
///
/// Unlike Combine's Publishers.ReceiveOn, ReceiveValuesOn only re-schedule
/// values and completion. It does not re-schedule subscription.
///
/// This scheduling guarantee is used by GRDBCombine in order to be able
/// to make promises on the scheduling of database values without surprising
/// the users as in https://forums.swift.org/t/28631.
struct ReceiveValuesOn<Upstream: Publisher, Context: Scheduler>: Publisher {
    typealias Output = Upstream.Output
    typealias Failure = Upstream.Failure
    
    fileprivate let upstream: Upstream
    fileprivate let context: Context
    fileprivate let options: Context.SchedulerOptions?
    
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = ReceiveValuesOnSubscription(
            upstream: upstream,
            context: context,
            options: options,
            downstream: subscriber)
        subscriber.receive(subscription: subscription)
    }
}

private class ReceiveValuesOnSubscription<Upstream: Publisher, Context: Scheduler, Downstream: Subscriber>: Subscription, Subscriber
    where Upstream.Failure == Downstream.Failure, Upstream.Output == Downstream.Input
{
    private struct Target {
        let context: Context
        let options: Context.SchedulerOptions?
        let downstream: Downstream
    }
    
    private enum State {
        case waitingForRequest(Upstream, Target)
        case waitingForSubscription(Target, Subscribers.Demand)
        case subscribed(Target, Subscription)
        case finished
    }
    
    private var state: State
    private let lock = NSRecursiveLock()
    
    init(
        upstream: Upstream,
        context: Context,
        options: Context.SchedulerOptions?,
        downstream: Downstream)
    {
        let target = Target(context: context, options: options, downstream: downstream)
        self.state = .waitingForRequest(upstream, target)
    }
    
    // MARK: Subscription
    
    func request(_ demand: Subscribers.Demand) {
        lock.synchronizedWithSideEffect {
            switch state {
            case let .waitingForRequest(upstream, target):
                state = .waitingForSubscription(target, demand)
                return {
                    upstream.receive(subscriber: self)
                }
                
            case let .waitingForSubscription(target, currentDemand):
                state = .waitingForSubscription(target, demand + currentDemand)
                return noSideEffect
                
            case let .subscribed(_, subcription):
                return {
                    subcription.request(demand)
                }
                
            case .finished:
                return noSideEffect
            }
        }
    }
    
    func cancel() {
        lock.synchronizedWithSideEffect {
            switch state {
            case .waitingForRequest, .waitingForSubscription:
                state = .finished
                return noSideEffect
                
            case let .subscribed(_, subcription):
                state = .finished
                return {
                    subcription.cancel()
                }
                
            case .finished:
                return noSideEffect
            }
        }
    }
    
    // MARK: Subscriber
    
    func receive(subscription: Subscription) {
        lock.synchronizedWithSideEffect {
            switch state {
            case let .waitingForSubscription(target, currentDemand):
                state = .subscribed(target, subscription)
                return {
                    subscription.request(currentDemand)
                }
                
            case .waitingForRequest, .subscribed, .finished:
                preconditionFailure()
            }
        }
    }
    
    func receive(_ input: Upstream.Output) -> Subscribers.Demand {
        lock.synchronizedWithSideEffect {
            switch state {
            case let .subscribed(target, _):
                return {
                    target.context.schedule(options: target.options) {
                        self._receive(input)
                    }
                }
            case .waitingForRequest, .waitingForSubscription, .finished:
                return noSideEffect
            }
        }
        
        // TODO: what problem are we creating by returning .unlimited and
        // ignoring downstream's result?
        //
        // `Publisher.receive(on:options:)` does not document its behavior
        // regarding backpressure.
        return .unlimited
    }
    
    func receive(completion: Subscribers.Completion<Upstream.Failure>) {
        lock.synchronizedWithSideEffect {
            switch state {
            case .waitingForRequest, .waitingForSubscription:
                return noSideEffect
            case let .subscribed(target, _):
                return {
                    target.context.schedule(options: target.options) {
                        self._receive(completion: completion)
                    }
                }
            case .finished:
                return noSideEffect
            }
        }
    }
    
    private func _receive(_ input: Upstream.Output) {
        lock.synchronizedWithSideEffect {
            switch state {
            case .waitingForRequest, .waitingForSubscription:
                return noSideEffect
            case let .subscribed(target, _):
                // TODO: don't ignore demand
                return {
                    _ = target.downstream.receive(input)
                }
            case .finished:
                return noSideEffect
            }
        }
    }
    
    private func _receive(completion: Subscribers.Completion<Upstream.Failure>) {
        lock.synchronizedWithSideEffect {
            switch state {
            case .waitingForRequest, .waitingForSubscription:
                return noSideEffect
            case let .subscribed(target, _):
                state = .finished
                return {
                    target.downstream.receive(completion: completion)
                }
            case .finished:
                return noSideEffect
            }
        }
    }
}

extension Publisher {
    /// Specifies the scheduler on which to receive values from the publisher
    ///
    /// The difference with the stock `receive(on:options:)` Combine method is
    /// that only values and completion are re-scheduled. Subscriptions are not.
    func receiveValues<S: Scheduler>(on scheduler: S, options: S.SchedulerOptions? = nil) -> ReceiveValuesOn<Self, S> {
        return ReceiveValuesOn(upstream: self, context: scheduler, options: options)
    }
}
