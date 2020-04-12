extension DatabasePublishers.Value {
    @available(*, unavailable, message: "Use scheduling(.immediate) instead")
    public func fetchOnSubscription() -> Self {
        preconditionFailure()
    }
}
