import Testing
@testable import SwiftSlashEventTrigger
import __cswiftslash_posix_helpers
import SwiftSlashFHHelpers
import SwiftSlashFIFO
import SwiftSlashFuture
import SwiftSlash

extension Tag {
	@Tag internal static var swiftSlashEventTrigger:Self
}

extension SwiftSlashTests {
	@Suite("SwiftSlashEventTrigger", 
		.serialized,
		.tags(.swiftSlashEventTrigger)
	)
	struct EventTriggerTests {
		@Test("SwiftSlashEventTrigger :: initialization", .timeLimit(.minutes(1)))
		func initializationBasics() async throws {
			var et:EventTrigger? = try await EventTrigger<DataChannel.ChildReadParentWrite.Error, DataChannel.ChildWriteParentRead.Error>()
			#expect(et != nil)
			et = nil
			#expect(et == nil)
		}
		@Test("SwiftSlashEventTrigger :: reading lifecycle simple", .timeLimit(.minutes(1)))
		func readingRegistration() async throws {
			let newPipe = try PosixPipe()
			let readingFIFO = FIFO<size_t, Never>()
			let asyncConsumer = readingFIFO.makeAsyncConsumer()
			let et:EventTrigger<DataChannel.ChildReadParentWrite.Error, DataChannel.ChildWriteParentRead.Error> = try await EventTrigger<DataChannel.ChildReadParentWrite.Error, DataChannel.ChildWriteParentRead.Error>()
			let fut = Future<Void, DataChannel.ChildWriteParentRead.Error>()
			fut.whenResult { result in
				readingFIFO.finish()
			}
			try await et.register(reader:newPipe.reading, readingFIFO, finishFuture:fut)
			#expect(try newPipe.writing.writeFH(singleByte:0x0) == 1)
			var nextItem:size_t? = await asyncConsumer.next()
			#expect(nextItem == 1, "readingFIFO should have 1 byte but instead found \(String(describing:nextItem))")
			#expect(fut.hasResult() == false, "readingFIFO should not have a result but instead found hasResult == \(String(describing:fut.hasResult()))")
			var myByte:UInt8 = 255
			#expect(try newPipe.reading.readFH(into:&myByte, size:1) == 1)
			#expect(myByte == 0x0, "readingFIFO should have read 0x0 but instead found \(String(describing:myByte))")
			try newPipe.writing.closeFileHandle()
			nextItem = await asyncConsumer.next()
			#expect(nextItem == nil, "readingFIFO should be nil but instead found \(String(describing:nextItem))")
			#expect(fut.hasResult() == true, "readingFIFO should have a result but instead found hasResult == \(String(describing:fut.hasResult()))")
			try newPipe.reading.closeFileHandle()
		}
		@Test("SwiftSlashEventTrigger :: writing lifecycle simple", .timeLimit(.minutes(1)))
		func writingRegistration() async throws {
			let newPipe = try PosixPipe()
			let writingFIFO = FIFO<Void, Never>()
			let asyncConsumer: FIFO<Void, Never>.AsyncConsumer = writingFIFO.makeAsyncConsumer()
			let et = try await EventTrigger<DataChannel.ChildReadParentWrite.Error, DataChannel.ChildWriteParentRead.Error>()
			let fut = Future<Void, DataChannel.ChildReadParentWrite.Error>()
			fut.whenResult { result in
				writingFIFO.finish()
			}
			try await et.register(writer:newPipe.writing, writingFIFO, finishFuture:fut)
			var nextItem:Void? = await asyncConsumer.next()
			#expect(nextItem != nil, "writingFIFO should not be nil but instead found nil")
			// #expect(fut.hasResult() == false, "writingFIFO should not have a result but instead found hasResult == \(String(describing:fut.hasResult()))")
			try newPipe.reading.closeFileHandle()
			nextItem = await asyncConsumer.next()
			#expect(nextItem == nil, "writingFIFO should be nil but instead found \(String(describing:nextItem))")
			// #expect(fut.hasResult() == true, "writingFIFO should have a result but instead found hasResult == \(String(describing:fut.hasResult()))")
			try newPipe.writing.closeFileHandle()
		}
	}
}