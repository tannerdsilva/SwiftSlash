import Foundation

internal typealias InboundDataHandler = (Data?) -> Void
internal typealias OutboundDataHandler = () -> Data
internal typealias DataChannelTerminationHander = () -> Void
internal typealias ProcessTerminationHandler = (Int32?) -> Void