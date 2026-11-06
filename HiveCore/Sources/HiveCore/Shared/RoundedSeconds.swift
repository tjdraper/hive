extension Duration {
    /// To the hundredth, for logs and answers.
    var roundedSeconds: Double {
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return (seconds * 100).rounded() / 100
    }
}
