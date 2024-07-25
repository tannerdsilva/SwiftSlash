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

public actor EventTrigger<ET:EventTriggerEngine> {

	/// the primitive that is used to handle the event trigger.
	private let prim:ET.EventTriggerHandle?

	/// the running pthread that is handling the event trigger.
	private let launchedThread:Running<Void>

	/// the stream of registrations that are being made to the event trigger.
	private let regStream:FIFO<Register>

	internal init() async throws {
		(self.prim, self.launchedThread, self.regStream) = try await ET.bootstrapEventTriggerService()
	}

	internal func register(reader:Int32, _ fifo:FIFO<size_t>) throws {
		try ET.register(prim!, reader:reader)
		regStream.yield(.reader(reader, fifo))
	}

	internal func register(writer:Int32, _ fifo:FIFO<Void>) throws {
		try ET.register(prim!, writer:writer)
		regStream.yield(.writer(writer, fifo))
	}
}

/// event trigger is an abstract term for a given platforms low-level event handling mechanism. this protocol is used to define the interface for the event trigger of each platform.
public protocol EventTriggerEngine:PThreadWork where Argument == Setup, ReturnType == Void, EventTriggerHandle == Int32 {

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
	fileprivate static func bootstrapEventTriggerService() async throws -> (Self.EventTriggerHandle, Running<Void>, FIFO<Register>) {
		let newP = Self.newPrimitive()
		let regStream = FIFO<Register>()
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
