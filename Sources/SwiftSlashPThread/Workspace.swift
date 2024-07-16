internal protocol PThreadWorkspace {
	associatedtype Argument
	associatedtype ReturnType
	init(_:Argument)
	mutating func run() throws -> ReturnType
}