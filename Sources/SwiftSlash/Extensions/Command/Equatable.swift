// MARK: - Equatable
extension Command:Equatable {
	public static func == (lhs:Command, rhs:Command) -> Bool {
		return (lhs.executable == rhs.executable) && (lhs.arguments == rhs.arguments) && (lhs.environment == rhs.environment)
	}
}