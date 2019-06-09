import Combine

typealias Cancellers = [AnyCancellable]

func += <Canceller: Cancellable>(bag: inout Cancellers, canceller: Canceller) {
    bag.append(AnyCancellable(canceller))
}
