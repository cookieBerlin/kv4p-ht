/// Waits until `condition` holds, for up to `timeout`: actors and streams deliver asynchronously, and tests running in
/// parallel share the cooperative pool, so a fixed number of yields is not enough on a busy machine.
public func eventually(
    isolation: isolated (any Actor)? = #isolation,
    timeout: Duration = .seconds(10),
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}
