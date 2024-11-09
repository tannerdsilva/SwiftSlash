import Testing
@testable import SwiftSlashFuture

@Suite("SwiftSlashFutureTests",
	.serialized
)
internal struct FutureTests {
	internal static func randomInt() -> Int {
		return Int.random(in:Int.min...Int.max)
	}
	internal static func randomString(length: Int) -> String {
		let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
		return String((0..<length).map{ _ in letters.randomElement()! })
	}

	@Test("SwiftSlashFuture :: initialize a future")
	internal func testInitializeFuture() {
		let future = Future<Int, Swift.Error>()
		#expect(future != nil)
	}

	@Test("SwiftSlashFuture :: test successful assignment with random integers")
	internal func setSuccessWithRandomIntegers() async throws {
		for _ in 0..<100 {
			var future:Future<Int, Never>? = Future<Int, Never>()
			let randomValue = Self.randomInt()
			try future!.setSuccess(randomValue)
			let result = await future!.result()
			var foundResult: Int? = nil
			switch result {
			case .success(let i):
				foundResult = i
			default:
				foundResult = nil
			}
			#expect(foundResult == randomValue)
			future = nil
		}
	}

	@Test("SwiftSlashFuture :: test successful assignment with edge integers")
	internal func testSetSuccessWithEdgeIntegers() async throws {
		let edgeValues = [Int.min, -1, 0, 1, Int.max]
		for value in edgeValues {
			var future: Future<Int, Never>? = Future<Int, Never>()
			try future!.setSuccess(value)
			let result = await future!.result()!
			var foundResult: Int? = nil
			switch result {
			case .success(let i):
				foundResult = i
			default:
				foundResult = nil
			}
			#expect(foundResult == value)
			future = nil
		}
	}

	@Test("SwiftSlashFuture :: test failure assignment with random integers")
	func testSetFailureWithRandomErrors() async throws {
		struct RandomTestError:Swift.Error, Equatable {
			let code:Int
			let message:String
			static func == (lhs: RandomTestError, rhs: RandomTestError) -> Bool {
				return lhs.code == rhs.code && lhs.message == rhs.message
			}
		}

		for _ in 0..<100 {
			let future = Future<Int, Swift.Error>()
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
		}
	}

	@Test("SwiftSlashFuture :: test results of random strings")
	func testAwaitResultWithRandomStrings() async throws {
		for _ in 0..<100 {
			let future: Future<String, Never>? = Future<String, Never>()
			let randomValue = Self.randomString(length: Int.random(in: 0...100))
			Task {
				try future!.setSuccess(randomValue)
			}
			let result = await future!.result()!
			var foundResult: String? = nil
			switch result {
			case .success(let s):
				foundResult = s
			case .failure:
				foundResult = nil
			}
			#expect(foundResult == randomValue)
		}
	}

	@Test("SwiftSlashFuture :: test success with large data")
	func testSetSuccessWithLargeData() async throws {
		var future: Future<[UInt8], Never>? = Future<[UInt8], Never>()
		let largeData = [UInt8](repeating:0xFF, count:10_000_000) // 10 MB of data
		try future!.setSuccess(largeData)
		let result = await future!.result()!
		var foundResult: [UInt8]? = nil
		switch result {
		case .success(let data):
			foundResult = data
		default:
			foundResult = nil
		}
		#expect(foundResult == largeData)
		future = nil
	}

	@Test("SwiftSlashFuture :: test failure assignment with varied errors")
	func testSetFailureWithEdgeErrors() async throws {
		struct EdgeTestError: Swift.Error, Equatable {
			let code: Int
			let message: String
			static func == (lhs: EdgeTestError, rhs: EdgeTestError) -> Bool {
				return lhs.code == rhs.code && lhs.message == rhs.message
			}
		}

		let edgeErrors = [
			EdgeTestError(code:Int.min, message:""),
			EdgeTestError(code:0, message:"zero error"),
			EdgeTestError(code:Int.max, message:String(repeating: "A", count: 1000))
		]

		for error in edgeErrors {
			let future = Future<Int, EdgeTestError>()
			try future.setFailure(error)
			let result = await future.result(throwingOnCurrentTaskCancellation:Never.self)
			var foundError:EdgeTestError? = nil
			switch result {
			case .failure(let e):
				foundError = e
			default:
				break
			}
			#expect(foundError == error)
		}
	}

	@Test("SwiftSlashFuture :: test async waiter with cancellation")
	func testAsyncWaiterCancellation() throws {
		let future = Future<Int, Never>()
		let cancelHandler = future.whenResult { r in 
			guard r == nil else {
				fatalError("result passed to whenResult when it should be cancelled: \(#file):\(#line)")
			}
		}
		let resultHandler = future.whenResult { r in
			guard r != nil else {
				fatalError("cancellation passed to whenResult when it should have been a result: \(#file):\(#line)")
			}
		}
		#expect(resultHandler != nil)
		#expect(cancelHandler != nil)
		#expect(future.cancel(waiterID:cancelHandler!) == true)

		try future.setSuccess(5)

		#expect(future.cancel(waiterID:resultHandler!) == false)
	}

	@Test("SwiftSlashFuture :: test blocking waiter")
	func testBlockingWaiter() throws {
		let future = Future<Int, Never>()
		Task {
			try future.setSuccess(5)
		}
		let result = future.blockingResult()!.get()
		#expect(result == 5)
	}
}