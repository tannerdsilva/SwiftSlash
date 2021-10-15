import Foundation

internal struct ReadableConfiguration {
	let fh:Int32
	let parseMode:DataParseMode
	let group:TerminationGroup
	let continuation:AsyncStream<Data>.Continuation
}
