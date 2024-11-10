import Testing
@testable import SwiftSlashFuture

extension SwiftSlashTests {
	@Suite("SwiftSlashFutureTests")
	internal struct FutureTests {
		internal static func randomInt() -> Int {
			return Int.random(in:Int.min...Int.max)
		}
		internal static func randomString(length:Int) -> String {
			let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
			return String((0..<length).map{ _ in letters.randomElement()! })
		}

		private var future:Future<Int, Swift.Error> = Future<Int, Swift.Error>()

		@Test("SwiftSlashFuture :: test successful assignment (random integer value)", .timeLimit(.minutes(1)))
		mutating internal func setSuccessWithRandomIntegers() async throws {
			for _ in 0..<100 {
				let randomValue = Self.randomInt()
				try future.setSuccess(randomValue)
				let result = await future.result()
				var foundResult: Int? = nil
				switch result {
				case .success(let i):
					foundResult = i
				default:
					foundResult = nil
				}
				#expect(foundResult == randomValue)
				future = Future<Int, Swift.Error>()
			}
		}

		@Test("SwiftSlashFuture :: test successful assignment with edge integers", .timeLimit(.minutes(1)))
		mutating internal func testSetSuccessWithEdgeIntegers() async throws {
			let edgeValues = [Int.min, -1, 0, 1, Int.max]
			for value in edgeValues {
				try future.setSuccess(value)
				let result = await future.result()!
				var foundResult: Int? = nil
				switch result {
				case .success(let i):
					foundResult = i
				default:
					foundResult = nil
				}
				#expect(foundResult == value)
				future = Future<Int, Swift.Error>()
			}
		}

		@Test("SwiftSlashFuture :: test failure assignment with random integers", .timeLimit(.minutes(1)))
		mutating func testSetFailureWithRandomErrors() async throws {
			struct RandomTestError:Swift.Error, Equatable {
				let code:Int
				let message:String
				static func == (lhs: RandomTestError, rhs: RandomTestError) -> Bool {
					return lhs.code == rhs.code && lhs.message == rhs.message
				}
			}

			for _ in 0..<100 {
				let error = RandomTestError(code: Self.randomInt(), message: Self.randomString(length: 20))
				try future.setFailure(error)
				let result = await future.result()!
				var foundError: RandomTestError? = nil
				switch result {
				case .failure(let e):
					if let e = e as? RandomTestError {
						foundError = e
					}
				default:
					break
				}
				#expect(foundError == error)
				future = Future<Int, Swift.Error>()
			}
		}

		@Test("SwiftSlashFuture :: test async waiter with cancellation", .timeLimit(.minutes(1)))
		func testAsyncWaiterCancellation() throws {
			let future = Future<Int, Never>()
			let cancelHandler = future.whenResult { r in 
				#expect(r == nil)
			}
			let resultHandler = future.whenResult { r in
				#expect(r != nil)
				switch r {
				case .success(let i):
					#expect(i == 5)
				default:
					break
				}
			}
			#expect(resultHandler != nil)
			#expect(cancelHandler != nil)
			#expect(future.cancel(waiterID:cancelHandler!) == true)

			try future.setSuccess(5)

			#expect(future.cancel(waiterID:resultHandler!) == false)
		}

		@Test("SwiftSlashFuture :: test blocking waiter", .timeLimit(.minutes(1)))
		func testBlockingWaiter() throws {
			let future = Future<Int, Never>()
			try future.setSuccess(5)
			let result = future.blockingResult()!.get()
			#expect(result == 5)
		}
	}
}