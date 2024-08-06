/// a process may only launch one child process at a time. nothing about the process of launching a child is reentrant safe. this actor enforces this rule.
@globalActor internal actor SerializedLaunch:GlobalActor {
	internal static let shared = SerializedLaunch()
}
