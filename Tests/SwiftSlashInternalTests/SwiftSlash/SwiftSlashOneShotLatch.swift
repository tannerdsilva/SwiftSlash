import Testing
@testable import SwiftSlashOneShotLatch

extension Tag {
	@Tag internal static var swiftSlashOneShotLatch:Self
}

extension SwiftSlashTests {
	@Suite("SwiftSlashOneShotLatchTests",
		.serialized,
		.tags(.swiftSlashOneShotLatch)
	)
	internal struct OneShotLatchTests {
		@Test("SwiftSlashOneShotLatch :: confirm deinit after unlock - no wait", .timeLimit(.minutes(1)))
		func testOneShotLatchMemoryManagement() async throws {
			try await confirmation("confirm correct memory management throughout lifecycle", expectedCount:1) { deinitConf in
				let latch = WhenDeinitTool(OneShotLatch<Void>(), deinitConf)
				try latch.value.fire(())
			}
		}
	}
}