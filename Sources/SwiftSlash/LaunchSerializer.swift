/// a process may only launch one child process at a time. no step in regards to producing a child process is reentrant safe. this actor enforces this strictly.
@globalActor internal actor SerializedLaunch:GlobalActor {
	internal static let shared = SerializedLaunch()
}
