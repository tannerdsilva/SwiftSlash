/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_eventtrigger
import SwiftSlashPThread
import SwiftSlashFIFO
import SwiftSlashFHHelpers
import SwiftSlashFuture

/// used to monitor file handles for activity.
public final class EventTrigger:Sendable {

	#if os(Linux)
	internal typealias PlatformSpecificETImplementation = LinuxEventTrigger
	#elseif os(macOS)
	internal typealias PlatformSpecificETImplementation = MacOSEventTrigger
	#endif

	/// the type of registration that is being made to the event trigger for readers.
	public typealias ReaderFIFO = FIFO<size_t, Never>
	/// the type of registration that is being made to the event trigger for writers.
	public typealias WriterFIFO = FIFO<Void, Never>

	/// the primitive that is used to handle the event trigger.
	private let prim:PlatformSpecificETImplementation.EventTriggerHandlePrimitive
	/// the running pthread that is handling the event trigger.
	private let launchedThread:Running<PlatformSpecificETImplementation>
	/// the stream of registrations that are being made to the event trigger. the system kernel allows for the file handle to be registered on any thread, but the corresponding FIFO must be passed to the pthread that is triggering the events
	private let regStream:FIFO<Register, Never>
	/// the type of registration that is being made to the event trigger.
	private let cancelPipe:PosixPipe

	/// initialize a new event trigger. will immediately open a new system primitive for polling, launch a pthread to handle the polling.
	public init() throws {
		cancelPipe = try PosixPipe()
		regStream = FIFO<Register, Never>()
		let p = try PlatformSpecificETImplementation.newHandlePrimitive()
		prim = p
		let lt:Running<PlatformSpecificETImplementation>
		do {
			lt = try PlatformSpecificETImplementation.launch(EventTriggerSetup(handle:p, registersIn:regStream, cancelPipe:cancelPipe))
		} catch let error {
			try PlatformSpecificETImplementation.closePrimitive(p)
			throw error
		}
		launchedThread = lt
		try PlatformSpecificETImplementation.register(p, reader:cancelPipe.reading)
	}

	/// registers a file handle (that is intended to be read from) with the event trigger for active monitoring.
	public borrowing func register(reader:Int32, _ fifo:consuming ReaderFIFO, finishFuture:consuming Future<Void, Never>) throws(EventTriggerErrors) {
		regStream.yield(.reader(fh:reader, (fifo, finishFuture)))
		try PlatformSpecificETImplementation.register(prim, reader:reader)
	}

	/// registers a file handle (that is intended to be written to) with the event trigger for active monitoring.
	public borrowing func register(writer:Int32, _ fifo:consuming WriterFIFO, finishFuture:consuming Future<Void, Never>) throws(EventTriggerErrors) {
		regStream.yield(.writer(fh:writer, (fifo, finishFuture)))
		try PlatformSpecificETImplementation.register(prim, writer:writer)
	}

	/// deregisters a file handle. the reader must be of reader variant. if the handle is not of reader variant, behavior is undefined.
	public borrowing func deregister(reader:Int32) throws {
		try PlatformSpecificETImplementation.deregister(prim, reader:reader)
		regStream.yield(.reader(fh:reader, nil))
	}

	/// deregisters a file handle. the handle must be of writer variant. if the handle is not of writer variant, behavior is undefined.
	public borrowing func deregister(writer:Int32) throws {
		try PlatformSpecificETImplementation.deregister(prim, writer:writer)
		regStream.yield(.writer(fh:writer, nil))
	}

	deinit {
		// cancel the thread since it will still be running at this point
		try! launchedThread.cancel()
		// signal to the polling infrastructure to unblock
		_ = try! cancelPipe.writing.writeFH(singleByte:0x0)
		// join the pthread
		try! launchedThread.joinSync()
		// deregister the cancel pipe from the event trigger
		try! PlatformSpecificETImplementation.deregister(prim, reader:cancelPipe.reading)
		// close the polling primitive
		try! PlatformSpecificETImplementation.closePrimitive(prim)
		// cancel pipe has served its purpose so we can close it
		try! cancelPipe.writing.closeFileHandle()
		// close the writing end of the close pipe
		try! cancelPipe.reading.closeFileHandle()
	}
}
