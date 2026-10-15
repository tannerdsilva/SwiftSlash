/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  /
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/ 

*/

import Testing
@testable import SwiftSlash
import SwiftSlashFHHelpers
import __cswiftslash_posix_helpers

extension SwiftSlashTests {
	@Suite("SwiftSlashFHHelpersTests",
		.serialized
	)
	struct SwiftSlashFHHelpersTests {

		/// an empty non-blocking descriptor with a live write end is a
		/// would-block condition, not a wait. the read must report it so the
		/// caller can park on a readiness signal — retrying inside the read
		/// burns a cooperative thread at 100% cpu with no suspension point, so
		/// the caller can neither finish nor be cancelled.
		@Test("SwiftSlashFHHelpersTests :: a read on an empty non-blocking descriptor reports would-block",
			.timeLimit(.minutes(1))
		)
		func readOnEmptyNonBlockingDescriptorReportsWouldBlock() throws {
			let pipe = try PosixPipe(nonblockingReads:true)
			defer {
				try? pipe.reading.closeFileHandle()
				try? pipe.writing.closeFileHandle()
			}
			// the write end stays open and sends nothing: this is the state a
			// reader lands in whenever a surviving process holds the pipe open.
			var byte:UInt8 = 0
			do {
				let readCount = try pipe.reading.readFH(into:&byte, size:1)
				Issue.record("readFH returned \(readCount) on an empty non-blocking descriptor; expected .error_wouldblock")
			} catch let error as FileHandleError {
				guard case .error_wouldblock = error else {
					Issue.record("expected .error_wouldblock from an empty non-blocking read, got \(error)")
					return
				}
			}
		}
	}
}