/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import SwiftSlashPThread
import SwiftSlashFHHelpers
import SwiftSlashGlobalSerialization

/// event trigger is an abstract term for a given platforms low-level event handling mechanism. this protocol is used to define the interface for the event trigger of each platform.
internal protocol EventTriggerEngine:PThreadWork where ArgumentType == EventTriggerSetup<EventTriggerHandlePrimitive>, ReturnType == Void, EventTriggerHandlePrimitive == Int32 {
	
	/// registers a file handle (that is intended to be read from) with the event trigger for active monitoring.
	@SwiftSlashGlobalSerialization static func register(_ ev:EventTriggerHandlePrimitive, reader:Int32) throws(EventTriggerErrors)

	/// registers a file handle (that is intended to be written to) with the event trigger for active monitoring.
	@SwiftSlashGlobalSerialization static func register(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors)

	/// deregisters a file handle. the reader must be of reader variant. if the handle is not of reader variant, behavior is undefined.
	static func deregister(_ ev:EventTriggerHandlePrimitive, reader:Int32) throws(EventTriggerErrors)

	/// deregisters a file handle. the handle must be of writer variant. if the handle is not of writer variant, behavior is undefined.
	static func deregister(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors)
	
	/// the type of primitive that this particular event trigger uses.
	associatedtype EventTriggerHandlePrimitive

	/// the primitive that is used to handle the event trigger.
	var prim:EventTriggerHandlePrimitive { get }

	/// creates a new primitive for the event trigger.
	static func newHandlePrimitive() throws(FileHandleError) -> EventTriggerHandlePrimitive

	/// closes the primitive for the event trigger.
	static func closePrimitive(_ prim:consuming EventTriggerHandlePrimitive) throws(FileHandleError)
}