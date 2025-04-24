import Testing
@testable import SwiftSlashEventTrigger
import __cswiftslash_posix_helpers
import SwiftSlashFHHelpers
import SwiftSlashFIFO

extension Tag {
	@Tag internal static var swiftSlashEventTrigger:Self
}

extension SwiftSlashTests {
	@Suite("SwiftSlashEventTrigger", 
		.serialized,
		.tags(.swiftSlashFIFO)
	)
	struct EventTriggerTests {
		@Test("SwiftSlashEventTrigger :: initialization", .timeLimit(.minutes(1)))
		func initializationBasics() throws {
			var et:EventTrigger? = try EventTrigger()
			#expect(et != nil)
			et = nil
			#expect(et == nil)
		}
		@Test("SwiftSlashEventTrigger :: reading registration", .timeLimit(.minutes(1)))
		func readingRegistration() async throws {
			let newPipe = try PosixPipe()
			let readingFIFO = FIFO<size_t, Never>()
			let asyncConsumer = readingFIFO.makeAsyncConsumer()
			let et = try EventTrigger()
			try et.register(reader:newPipe.reading, readingFIFO)
			#expect(try newPipe.writing.writeFH(singleByte:0x0) == 1)
			let nextItem = await asyncConsumer.next()
			#expect(nextItem == 1, "readingFIFO should have 1 byte but instead found \(nextItem)")
			try et.deregister(reader:newPipe.reading)
			close(newPipe.reading)
			close(newPipe.writing)
		}
		@Test("SwiftSlashEventTrigger :: writing registration", .timeLimit(.minutes(1)))
		func writingRegistration() async throws {
			let newPipe = try PosixPipe()
			let writingFIFO = FIFO<Void, Never>()
			let asyncConsumer = writingFIFO.makeAsyncConsumer()
			let et = try EventTrigger()
			try et.register(writer:newPipe.writing, writingFIFO)
			let nextItem = await asyncConsumer.next()
			#expect(nextItem != nil, "writingFIFO should not be nil but instead found nil")
			try et.deregister(writer:newPipe.writing)
			close(newPipe.reading)
			close(newPipe.writing)
		}
	}
}