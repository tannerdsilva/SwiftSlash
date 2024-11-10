import SwiftSlashFuture

/// this is the primary protocol for implementing a work type that can safely initialize, run, and cancel from a pthread.
public protocol PThreadWork {
	/// the argument type that this work takes.
	associatedtype Argument:Sendable
	
	/// the return type that this work produces.
	associatedtype ReturnType:Sendable
	
	/// the type of error that the work can throw.
	associatedtype ThrowType:Swift.Error
	
	/// creates a new instance of the work type.
	init(_:consuming Argument)
	
	/// runs the work and returns the result.
	mutating func pthreadWork() throws(ThrowType) -> ReturnType
}