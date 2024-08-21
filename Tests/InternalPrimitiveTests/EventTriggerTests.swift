import XCTest
@testable import SwiftSlash
import SwiftSlashEventTrigger
import SwiftSlashFHHelpers

class EventTriggerTests: XCTestCase {
	func testRegisterReader() async throws {
		let eventTrigger = try await EventTrigger()
		let readerPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:false)
		let readerFIFO = EventTrigger.ReaderFIFO()
		let myReaderIterator = readerFIFO.makeAsyncConsumer()
		try eventTrigger.register(reader:readerPipe.reading, readerFIFO)
		XCTAssertEqual(try readerPipe.writing.writeFH([UInt8]("Hello, World!".utf8)), 13)
		var captured:[UInt8]? = nil
		thisThing: while let next = try await myReaderIterator.next() {
			XCTAssertEqual(next, 13)
			break thisThing
		}
	}
	
	// func testRegisterWriter() throws {
	// 	let eventTrigger = try EventTrigger()
	// 	let writer: Int32 = 456
	// 	try eventTrigger.register(writer: writer)
	// 	// Assert that the writer is registered successfully
	// 	// You can add your own assertions here
	// }
	
	// func testDeregisterReader() throws {
	// 	let eventTrigger = try EventTrigger()
	// 	let reader: Int32 = 123
	// 	try eventTrigger.deregister(reader: reader)
	// 	// Assert that the reader is deregistered successfully
	// 	// You can add your own assertions here
	// }
	
	// func testDeregisterWriter() throws {
	// 	let eventTrigger = try EventTrigger()
	// 	let writer: Int32 = 456
	// 	try eventTrigger.deregister(writer: writer)
	// 	// Assert that the writer is deregistered successfully
	// 	// You can add your own assertions here
	// }
}