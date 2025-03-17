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

/// used to monitor file handles for activity.
public final class EventTrigger:Sendable {

	#if os(Linux)
	internal typealias PlatformSpecificETImplementation = LinuxET
	#elseif os(macOS)
	internal typealias PlatformSpecificETImplementation = MacOSEventTrigger
	#endif

	/// the type of registration that is being made to the event trigger.
	public typealias ReaderFIFO = FIFO<size_t, Never>

	/// the type of registration that is being made to the event trigger.
	public typealias WriterFIFO = FIFO<Void, Never>

	/// the primitive that is used to handle the event trigger.
	private let prim:Int32?

	/// the running pthread that is handling the event trigger.
	private let launchedThread:Running<PlatformSpecificETImplementation>

	/// the stream of registrations that are being made to the event trigger. the system kernel allows for the file handle to be registered on any thread, but the corresponding FIFO must be passed to the pthread that is triggering the events
	private let regStream:FIFO<Register, Never>

	/// initialize a new event trigger. will immediately open a new system primitive for polling, launch a pthread to handle the polling.
	public init() async throws {
		regStream = FIFO<Register, Never>()
		let p = PlatformSpecificETImplementation.newHandlePrimitive()
		prim = p
		let lt:Running<PlatformSpecificETImplementation>
		do {
			lt = try await PlatformSpecificETImplementation.launch(EventTriggerSetup(handle:p, registersIn:regStream))
		} catch let error {
			PlatformSpecificETImplementation.closePrimitive(p)
			throw error
		}
		launchedThread = lt
	}

	/// registers a file handle (that is intended to be read from) with the event trigger for active monitoring.
	public borrowing func register(reader:Int32, _ fifo:ReaderFIFO) throws {
		regStream.yield(.reader(reader, fifo))
		try PlatformSpecificETImplementation.register(prim!, reader:reader)
	}

	/// registers a file handle (that is intended to be written to) with the event trigger for active monitoring.
	public borrowing func register(writer:Int32, _ fifo:WriterFIFO) throws {
		regStream.yield(.writer(writer, fifo))
		try PlatformSpecificETImplementation.register(prim!, writer:writer)
	}

	/// deregisters a file handle. the reader must be of reader variant. if the handle is not of reader variant, behavior is undefined.
	public borrowing func deregister(reader:Int32) throws {
		try PlatformSpecificETImplementation.deregister(prim!, reader:reader)
		regStream.yield(.reader(reader, nil))
	}

	/// deregisters a file handle. the handle must be of writer variant. if the handle is not of writer variant, behavior is undefined.
	public borrowing func deregister(writer:Int32) throws {
		try PlatformSpecificETImplementation.deregister(prim!, writer:writer)
		regStream.yield(.writer(writer, nil))
	}
}

/// event trigger is an abstract term for a given platforms low-level event handling mechanism. this protocol is used to define the interface for the event trigger of each platform.
public protocol EventTriggerEngine:PThreadWork where Argument == EventTriggerSetup<EventTriggerHandlePrimitive>, ReturnType == Void, EventTriggerHandlePrimitive == Int32 {
	/// the type of runtime error that might be thrown while the eventtrigger process is running. 
	associatedtype RuntimeErrors:Swift.Error

	/// registers a file handle (that is intended to be read from) with the event trigger for active monitoring.
	static func register(_ ev:EventTriggerHandlePrimitive, reader:Int32) throws(EventTriggerErrors)

	/// registers a file handle (that is intended to be written to) with the event trigger for active monitoring.
	static func register(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors)

	/// deregisters a file handle. the reader must be of reader variant. if the handle is not of reader variant, behavior is undefined.
	static func deregister(_ ev:EventTriggerHandlePrimitive, reader:Int32) throws(EventTriggerErrors)

	/// deregisters a file handle. the handle must be of writer variant. if the handle is not of writer variant, behavior is undefined.
	static func deregister(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors)
	
	/// the type of primitive that this particular event trigger uses.
	associatedtype EventTriggerHandlePrimitive

	/// the primitive that is used to handle the event trigger.
	var prim:EventTriggerHandlePrimitive { get }

	/// creates a new primitive for the event trigger.
	static func newHandlePrimitive() -> EventTriggerHandlePrimitive

	/// closes the primitive for the event trigger.
	static func closePrimitive(_ prim:consuming EventTriggerHandlePrimitive)
}