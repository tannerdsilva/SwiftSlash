import Foundation

internal typealias InboundDataHandler = (Data) -> Void
internal typealias OutboundDataHandler = () -> Data
internal typealias DataChannelTerminationHander = () -> Void
