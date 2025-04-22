import Testing
@testable import SwiftSlashEventTrigger

extension Tag {
	@Tag internal static var swiftSlashEventTrigger:Self
}

extension SwiftSlashTests {
	@Suite("SwiftSlashEventTrigger", 
		.serialized,
		.tags(.swiftSlashFIFO)
	)
	struct EventTriggerTests {
		@Test("SwiftSlashEventTrigger :: initialization")
		func initializationBasics() throws {
			/*let et = try EventTrigger()*/
		}
	}
}