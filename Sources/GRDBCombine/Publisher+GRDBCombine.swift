import Combine

extension Publisher {
    /// Returns a publisher of Result
    func eraseToResult() -> AnyPublisher<Result<Output, Failure>, Never> {
        return map { Result<Output, Failure>.success($0) }
            .catch { Just(Result<Output, Failure>.failure($0)) }
            .eraseToAnyPublisher()
    }
    
    /// Specifies the scheduler on which to receive elements from the publisher
    ///
    /// The difference with the stock `receive(on:options:)` Combine method is
    /// that only values and completion are re-scheduled. Subscriptions are not.
    func receiveValue<S: Scheduler>(on scheduler: S, options: S.SchedulerOptions? = nil) -> ReceiveValueOn<Self, S> {
        return ReceiveValueOn(upstream: self, context: scheduler, options: options)
    }
}

struct ReceiveValueOn<Upstream: Publisher, Context: Scheduler>: Publisher {
    typealias Output = Upstream.Output
    typealias Failure = Upstream.Failure
    
    fileprivate let upstream: Upstream
    fileprivate let context: Context
    fileprivate let options: Context.SchedulerOptions?
    
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        upstream.receive(subscriber: ReceiveValueOnSubscriber(downstream: subscriber, context: context, options: options))
    }
    
    struct ReceiveValueOnSubscriber<Downstream: Subscriber>: Subscriber {
        let combineIdentifier = CombineIdentifier()
        let downstream: Downstream
        let context: Context
        let options: Context.SchedulerOptions?
        
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
}
