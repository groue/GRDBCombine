extension DatabasePublishers.Value {
    @available(*, unavailable, message: "Use publisher(in: ..., scheduling: .immediate) instead")
    public func fetchOnSubscription() -> Self {
        preconditionFailure()
    }
}
