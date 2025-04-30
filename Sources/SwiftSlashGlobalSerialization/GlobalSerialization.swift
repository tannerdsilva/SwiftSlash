/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

/// a process may only launch one child process at a time. no step in regards to producing a child process is reentrant safe. this actor enforces this strictly.
@globalActor public actor SwiftSlashGlobalSerialization:GlobalActor {
	/// the global actor that is used to serialize the launch of child processes.
	public static let shared = SwiftSlashGlobalSerialization()
}