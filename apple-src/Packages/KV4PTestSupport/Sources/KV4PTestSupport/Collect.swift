/// The first `count` elements of `stream`; fewer if it finishes earlier.
public func collect<Element>(_ count: Int, from stream: AsyncStream<Element>) async -> [Element] {
    var elements: [Element] = []
    for await element in stream.prefix(count) {
        elements.append(element)
    }
    return elements
}
