/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

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
import SwiftSlashGlobalSerialization

/// used to monitor file handles for activity.
public final class EventTrigger:Sendable {

	#if os(Linux)
	internal typealias PlatformSpecificETImplementation = LinuxEventTrigger
	#elseif os(macOS)
	internal typealias PlatformSpecificETImplementation = MacOSEventTrigger
	#endif

	/// the type of registration that is being made to the event trigger for readers.
	public typealias ReaderFIFO = FIFO<Int, Never>
	/// the type of registration that is being made to the event trigger for writers.
	public typealias WriterFIFO = FIFO<Void, Never>

	/// the primitive that is used to handle the event trigger.
	private let prim:PlatformSpecificETImplementation.EventTriggerHandlePrimitive
	/// the running pthread that is handling the event trigger.
	private let launchedThread:Running<PlatformSpecificETImplementation>
	/// the stream of registrations that are being made to the event trigger. the system kernel allows for the file handle to be registered on any thread, but the corresponding FIFO must be passed to the pthread that is triggering the events
	private let regStream:FIFO<(Int32, Register?), Never>
	/// the type of registration that is being made to the event trigger.
	private let cancelPipe:PosixPipe

	/// initialize a new event trigger. will immediately open a new system primitive for polling, launch a pthread to handle the polling.
	@SwiftSlashGlobalSerialization public init() throws {
		cancelPipe = try PosixPipe()
		regStream = try! FIFO()
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
	@SwiftSlashGlobalSerialization public borrowing func register(reader:Int32, _ fifo:consuming ReaderFIFO, finishFuture:consuming Future<Void, Never>) throws(EventTriggerErrors) {
		regStream.yield((reader, .reader(fifo, finishFuture)))
		try PlatformSpecificETImplementation.register(prim, reader:reader)
	}

	/// registers a file handle (that is intended to be written to) with the event trigger for active monitoring.
	@SwiftSlashGlobalSerialization public func register(writer:Int32, _ fifo:consuming WriterFIFO, finishFuture:consuming Future<Void, Never>) throws(EventTriggerErrors) {
		regStream.yield((writer, .writer(fifo, finishFuture)))
		try PlatformSpecificETImplementation.register(prim, writer:writer)
	}

	/// deregisters a file handle. the reader must be of reader variant. if the handle is not of reader variant, behavior is undefined.
	public borrowing func deregister(reader:Int32) throws {
		try PlatformSpecificETImplementation.deregister(prim, reader:reader)
		regStream.yield((reader, nil))
	}

	/// deregisters a file handle. the handle must be of writer variant. if the handle is not of writer variant, behavior is undefined.
	public borrowing func deregister(writer:Int32) throws {
		try PlatformSpecificETImplementation.deregister(prim, writer:writer)
		regStream.yield((writer, nil))
	}

	/// registers a process for exit monitoring. the provided FIFO will receive a single element when the monitored process exits.
	/// - NOTE: monitoring is performed by the event trigger's polling thread, so the FIFO recipient will be signaled even if the registering task is cancelled before the process exits.
	@SwiftSlashGlobalSerialization public borrowing func register(process pid:pid_t, _ fifo:consuming FIFO<Int, Never>) throws(EventTriggerErrors) {
		regStream.yield((pid, .process(fifo)))
		try PlatformSpecificETImplementation.register(prim, process:pid)
	}

	/// deregisters a process exit monitor.
	@SwiftSlashGlobalSerialization public borrowing func deregister(process pid:pid_t) throws {
		// enqueue the removal BEFORE the kernel call: if the platform deregistration
		// throws, the stream entry has already removed the monitor from the trigger's
		// active set, so no stale entry can linger.
		regStream.yield((pid, nil))
		try PlatformSpecificETImplementation.deregister(prim, process:pid)
	}

	/// removes a pending process-exit registration from the registration stream without
	/// touching the kernel. used to clean up when a platform registration fails: the
	/// registration is enqueued before the kernel call so no exit event can be lost, and a
	/// failing kernel call would otherwise leave a stale `.process` entry installed forever.
	@SwiftSlashGlobalSerialization public borrowing func dropProcessRegistration(_ pid:pid_t) {
		regStream.yield((pid, nil))
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
