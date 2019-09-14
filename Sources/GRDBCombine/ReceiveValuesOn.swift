import Combine

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
        upstream.receive(subscriber: ReceiveValuesOnSubscriber(
            downstream: subscriber,
            context: context,
            options: options))
    }
}

private struct ReceiveValuesOnSubscriber<Downstream: Subscriber, Context: Scheduler>: Subscriber {
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
    /// Specifies the scheduler on which to receive values from the publisher
    ///
    /// The difference with the stock `receive(on:options:)` Combine method is
    /// that only values and completion are re-scheduled. Subscriptions are not.
    func receiveValues<S: Scheduler>(on scheduler: S, options: S.SchedulerOptions? = nil) -> ReceiveValuesOn<Self, S> {
        return ReceiveValuesOn(upstream: self, context: scheduler, options: options)
    }
}

