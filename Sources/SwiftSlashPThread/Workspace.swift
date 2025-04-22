/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_threads

/// this is the primary protocol for implementing a work type that can safely initialize, run, and cancel from a pthread.
public protocol PThreadWork {
	/// the argument type that this work takes.
	associatedtype ArgumentType:Sendable
	
	/// the return type that this work produces.
	associatedtype ReturnType:Sendable
	
	/// the type of error that the work can throw.
	associatedtype ThrowType:Swift.Error
	
	/// creates a new instance of the work type.
	init(_:consuming ArgumentType)
	
	/// runs the work and returns the result.
	mutating func pthreadWork() throws(ThrowType) -> ReturnType
}