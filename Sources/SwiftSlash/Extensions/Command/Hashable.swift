// MARK: - Hashable
extension Command:Hashable {
	public func hash(into hasher:inout Hasher) {
		hasher.combine(executable)
		hasher.combine(arguments)
		hasher.combine(environment)
	}
}