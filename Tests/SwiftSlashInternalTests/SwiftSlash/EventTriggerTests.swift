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
		@Test("SwiftSlashEventTrigger :: initialization", .timeLimit(.minutes(1)))
		func initializationBasics() throws {
			var et:EventTrigger? = try EventTrigger()
			#expect(et != nil)
			et = nil
			#expect(et == nil)
		}
	}
}