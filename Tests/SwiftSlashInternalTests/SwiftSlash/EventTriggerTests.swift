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
		func initializationBasics() async throws {
			var et:EventTrigger? = try EventTrigger()
			#expect(et != nil)
			et = nil
			#expect(et == nil)
		}
		@Test("SwiftSlashEventTrigger :: reading lifecycle simple", .timeLimit(.minutes(1)))
		func readingRegistration() async throws {
			let newPipe = try PosixPipe()
			let readingFIFO = FIFO<size_t, Never>()
			let asyncConsumer = readingFIFO.makeAsyncConsumer()
			let et = try EventTrigger()
			try et.register(reader:newPipe.reading, readingFIFO)
			#expect(try newPipe.writing.writeFH(singleByte:0x0) == 1)
			var nextItem:size_t? = await asyncConsumer.next()
			#expect(nextItem == 1, "readingFIFO should have 1 byte but instead found \(String(describing:nextItem))")
			var myByte:UInt8 = 255
			#expect(try newPipe.reading.readFH(into:&myByte, size:1) == 1)
			#expect(myByte == 0x0, "readingFIFO should have read 0x0 but instead found \(String(describing:myByte))")
			try newPipe.writing.closeFileHandle()
			nextItem = await asyncConsumer.next()
			#expect(nextItem == nil, "readingFIFO should be nil but instead found \(String(describing:nextItem))")
			try et.deregister(reader:newPipe.reading)
			try newPipe.reading.closeFileHandle()
		}
		@Test("SwiftSlashEventTrigger :: writing lifecycle simple", .timeLimit(.minutes(1)))
		func writingRegistration() async throws {
			let newPipe = try PosixPipe()
			let writingFIFO = FIFO<Void, Never>()
			let asyncConsumer: FIFO<Void, Never>.AsyncConsumer = writingFIFO.makeAsyncConsumer()
			let et = try EventTrigger()
			try et.register(writer:newPipe.writing, writingFIFO)
			var nextItem:Void? = await asyncConsumer.next()
			#expect(nextItem != nil, "writingFIFO should not be nil but instead found nil")
			try newPipe.reading.closeFileHandle()
			nextItem = await asyncConsumer.next()
			#expect(nextItem == nil, "writingFIFO should be nil but instead found \(String(describing:nextItem))")
			try et.deregister(writer:newPipe.writing)
			try newPipe.writing.closeFileHandle()
		}
	}
}