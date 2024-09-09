import __cswiftslash
import SwiftSlashPThread
import SwiftSlashFIFO

#if os(Linux)
import Glibc
internal let currentPlatformET = LinuxET.self
#elseif os(macOS)
import Darwin
internal let currentPlatformET = MacOSImpl.self
#endif

/// used to monitor file handles for activity.
public struct EventTrigger {

	/// the type of registration that is being made to the event trigger.
	public typealias ReaderFIFO = FIFO<size_t, Swift.Error>

	/// the type of registration that is being made to the event trigger.
	public typealias WriterFIFO = FIFO<Void, Swift.Error>

	/// the primitive that is used to handle the event trigger.
	private let prim:Int32?

	/// the running pthread that is handling the event trigger.
	private let launchedThread:Running<Void>

	/// the stream of registrations that are being made to the event trigger. the system kernel allows for the file handle to be registered on any thread, but the corresponding FIFO must be passed to the pthread that is triggering the events
	private let regStream:FIFO<Register, Never>

	/// initialize a new event trigger. will immediately open a new system primitive for polling, launch a pthread to handle the polling.
	public init() async throws {
		(self.prim, self.launchedThread, self.regStream) = try await currentPlatformET.bootstrapEventTriggerService()
	}

	/// registers a file handle (that is intended to be read from) with the event trigger for active monitoring.
	public borrowing func register(reader:Int32, _ fifo:ReaderFIFO) throws {
		regStream.yield(.reader(reader, fifo))
		try currentPlatformET.register(prim!, reader:reader)
	}

	/// registers a file handle (that is intended to be written to) with the event trigger for active monitoring.
	public borrowing func register(writer:Int32, _ fifo:WriterFIFO) throws {
		regStream.yield(.writer(writer, fifo))
		try currentPlatformET.register(prim!, writer:writer)
	}

	/// deregisters a file handle. the reader must be of reader variant. if the handle is not of reader variant, behavior is undefined.
	public borrowing func deregister(reader:Int32) throws {
		try currentPlatformET.deregister(prim!, reader:reader)
		regStream.yield(.reader(reader, nil))
	}

	/// deregisters a file handle. the handle must be of writer variant. if the handle is not of writer variant, behavior is undefined.
	public borrowing func deregister(writer:Int32) throws {
		try currentPlatformET.deregister(prim!, writer:writer)
		regStream.yield(.writer(writer, nil))
	}
}

/// event trigger is an abstract term for a given platforms low-level event handling mechanism. this protocol is used to define the interface for the event trigger of each platform.
public protocol EventTriggerEngine:PThreadWork where Argument == Setup, ReturnType == Void, EventTriggerHandle == Int32 {
	/// the type of runtime error that might be thrown while the eventtrigger process is running. 
	associatedtype RuntimeErrors:Swift.Error

	/// registers a file handle (that is intended to be read from) with the event trigger for active monitoring.
	static func register(_ ev:EventTriggerHandle, reader:Int32) throws

	/// registers a file handle (that is intended to be written to) with the event trigger for active monitoring.
	static func register(_ ev:EventTriggerHandle, writer:Int32) throws

	/// deregisters a file handle. the reader must be of reader variant. if the handle is not of reader variant, behavior is undefined.
	static func deregister(_ ev:EventTriggerHandle, reader:Int32) throws

	/// deregisters a file handle. the handle must be of writer variant. if the handle is not of writer variant, behavior is undefined.
	static func deregister(_ ev:EventTriggerHandle, writer:Int32) throws
	
	/// the type of primitive that this particular event trigger uses.
	associatedtype EventTriggerHandle

	/// the primitive that is used to handle the event trigger.
	var prim:EventTriggerHandle { get }

	/// creates a new primitive for the event trigger.
	static func newPrimitive() -> EventTriggerHandle

	/// closes the primitive for the event trigger.
	static func closePrimitive(_ prim:consuming EventTriggerHandle)
}

extension EventTriggerEngine {
	/// launches a new event trigger service.
	/// - async: waits for the event trigger service to be launched and running on a dedicated pthread before yielding back to the calling task.
	/// - returns: the event trigger handle, the running pthread, and the FIFO that is used to register new file handles.
	internal static func bootstrapEventTriggerService() async throws -> (Self.EventTriggerHandle, Running<Void>, FIFO<Register, Never>) {
		let newP = Self.newPrimitive()
		let regStream = FIFO<Register, Never>()
		let launchedThread:Running<Void>
		do {
			launchedThread = try await Self.launch(Setup(handle:newP, registersIn:regStream))
		} catch let error {
			Self.closePrimitive(newP)
			throw error
		}
		return (newP, launchedThread, regStream)
	}
}
