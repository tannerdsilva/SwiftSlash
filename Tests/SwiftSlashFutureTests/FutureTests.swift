import Testing
@testable import SwiftSlashFuture

@Suite("SwiftSlashFutureTests")
internal struct FutureTests {

    // Helper function to generate random integers
    static func randomInt() -> Int {
        return Int.random(in: Int.min...Int.max)
    }

    // Helper function to generate random strings
    static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }

    @Test("SwiftSlashFuture :: test successful assignment with random integers")
	func setSuccessWithRandomIntegers() async throws {
        for _ in 0..<100 {
            var future: Future<Int>? = Future<Int>()
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

    @Test func testSetSuccessWithEdgeIntegers() async throws {
        let edgeValues = [Int.min, -1, 0, 1, Int.max]
        for value in edgeValues {
            var future: Future<Int>? = Future<Int>()
            try future!.setSuccess(value)
            let result = await future!.result()
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

    @Test func testSetFailureWithRandomErrors() async throws {
        struct RandomTestError: Swift.Error, Equatable {
            let code: Int
            let message: String

            static func == (lhs: RandomTestError, rhs: RandomTestError) -> Bool {
                return lhs.code == rhs.code && lhs.message == rhs.message
            }
        }

        for _ in 0..<100 {
            let future = Future<Int>()
            let error = RandomTestError(code: Self.randomInt(), message: Self.randomString(length: 20))
            try future.setFailure(error)
            let result = await future.result()
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

    @Test func testAwaitResultWithRandomStrings() async {
        for _ in 0..<100 {
            var future: Future<String>? = Future<String>()
            let randomValue = Self.randomString(length: Int.random(in: 0...100))
            Task {
                try future!.setSuccess(randomValue)
            }
            let result = await future!.result()
            var foundResult: String? = nil
            switch result {
            case .success(let s):
                foundResult = s
            case .failure:
                foundResult = nil
            }
            #expect(foundResult == randomValue)
            future = nil
        }
    }

    @Test func testSetSuccessWithLargeData() async throws {
        var future: Future<[UInt8]>? = Future<[UInt8]>()
        let largeData = [UInt8](repeating: 0xFF, count: 10_000_000) // 10 MB of data
        try future!.setSuccess(largeData)
        let result = await future!.result()
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

    @Test func testSetFailureWithEdgeErrors() async throws {
        struct EdgeTestError: Swift.Error, Equatable {
            let code: Int
            let message: String

            static func == (lhs: EdgeTestError, rhs: EdgeTestError) -> Bool {
                return lhs.code == rhs.code && lhs.message == rhs.message
            }
        }

        let edgeErrors = [
            EdgeTestError(code: Int.min, message: ""),
            EdgeTestError(code: 0, message: "zero error"),
            EdgeTestError(code: Int.max, message: String(repeating: "A", count: 1000))
        ]

        for error in edgeErrors {
            let future = Future<Int>()
            try future.setFailure(error)
            let result = await future.result()
            var foundError: EdgeTestError? = nil
            switch result {
            case .failure(let e):
                if let e = e as? EdgeTestError {
                    foundError = e
                }
            default:
                break
            }
            #expect(foundError == error)
        }
    }
}