import Combine

/// A publisher that delivers elements to its downstream subscriber on a
/// specific scheduler.
///
/// Unlike Combine's Publishers.ReceiveOn, ReceiveElementsOn only re-schedule
/// elements and completion. It does not re-schedule subscription.
///
/// This scheduling guarantee is used by GRDBCombine in order to be able
/// to make promises on the scheduling of database values without surprising
/// the users as in https://forums.swift.org/t/28631.
struct ReceiveElementsOn<Upstream: Publisher, Context: Scheduler>: Publisher {
    typealias Output = Upstream.Output
    typealias Failure = Upstream.Failure
    
    fileprivate let upstream: Upstream
    fileprivate let context: Context
    fileprivate let options: Context.SchedulerOptions?
    
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        upstream.receive(subscriber: ReceiveElementsOnSubscriber(
            downstream: subscriber,
            context: context,
            options: options))
    }
}

private struct ReceiveElementsOnSubscriber<Downstream: Subscriber, Context: Scheduler>: Subscriber {
    let combineIdentifier = CombineIdentifier()
    fileprivate let downstream: Downstream
    fileprivate let context: Context
    fileprivate let options: Context.SchedulerOptions?
    
    func receive(subscription: Subscription) {
        downstream.receive(subscription: subscription)
    }
    
    func receive(_ input: Downstream.Input) -> Subscribers.Demand {
        context.schedule(options: options) {
            _ = self.downstream.receive(input)
        }
        
        // TODO: what problem are we creating by returning .unlimited and
        // ignoring downstream's result?
        //
        // `Publisher.receive(on:options:)` does not document its behavior
        // regarding backpressure.
        return .unlimited
    }
    
    func receive(completion: Subscribers.Completion<Downstream.Failure>) {
        context.schedule(options: options) {
            self.downstream.receive(completion: completion)
        }
    }
}

extension Publisher {
    /// Specifies the scheduler on which to receive elements from the publisher
    ///
    /// The difference with the stock `receive(on:options:)` Combine method is
    /// that only elements and completion are re-scheduled.
    /// Subscriptions are not.
    func receiveElements<S: Scheduler>(on scheduler: S, options: S.SchedulerOptions? = nil) -> ReceiveElementsOn<Self, S> {
        return ReceiveElementsOn(upstream: self, context: scheduler, options: options)
    }
}

