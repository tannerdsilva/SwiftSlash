import Testing
import __cswiftslash_auint8

fileprivate final class AUInt8TestHarness:@unchecked Sendable {

	private let auint8Ptr:UnsafeMutablePointer<_cswiftslash_atomic_uint8_t>
	
	fileprivate init(_ value:UInt8) {
		self.auint8Ptr = UnsafeMutablePointer<_cswiftslash_atomic_uint8_t>.allocate(capacity: 1)
		self.auint8Ptr.initialize(to: _cswiftslash_auint8_init(value))
	}

	fileprivate func load() -> UInt8 {
		return _cswiftslash_auint8_load(self.auint8Ptr)
	}

	fileprivate func store(_ value:UInt8) {
		_cswiftslash_auint8_store(self.auint8Ptr, value)
	}

	fileprivate func compareExchangeWeak(expected:inout UInt8, desired:UInt8) -> Bool {
		return _cswiftslash_auint8_compare_exchange_weak(self.auint8Ptr, &expected, desired)
	}

	deinit {
		self.auint8Ptr.deinitialize(count:1)
		self.auint8Ptr.deallocate()
	}
}

// Test for loading and storing atomic uint8_t values.
@Test("__cswiftslash_auint8 :: load and store tests", arguments: Array(0...255))
func testAtomicUInt8LoadStore(value: UInt8) {
    // Initialize the atomic uint8_t test harness
    let atomicValue = AUInt8TestHarness(value)
    
    // Load the value
    let loadedValue = atomicValue.load()
    
    // Verify that the loaded value matches the initialized value
    #expect(loadedValue == value)
    
    // Store a new value
    let newValue: UInt8 = UInt8.random(in: 0...255)
    atomicValue.store(newValue)
    
    // Load the value again
    let updatedValue = atomicValue.load()
    
    // Verify that the loaded value matches the new value
    #expect(updatedValue == newValue)
}

// Test for compare_exchange_weak success scenario
@Test("__cswiftslash_auint8 :: compare exchange weak success tests", arguments:Array(0...255))
func testAtomicUInt8CompareExchangeWeakSuccess(initialValue:UInt8) {
    // Initialize the atomic uint8_t test harness with the initial value
    let atomicValue = AUInt8TestHarness(initialValue)
    
    // Expected value is the same as the initial value
    var expected = initialValue
    
    // New value to store
    let newValue: UInt8 = UInt8.random(in: 0...255)
    
    // Perform compare_exchange_weak
    let result = atomicValue.compareExchangeWeak(expected: &expected, desired: newValue)
    
    // Expect the operation to succeed
    #expect(result == true)
    
    // Verify that the new value was stored
    let loadedValue = atomicValue.load()
    #expect(loadedValue == newValue)
}

// Test for compare_exchange_weak failure scenario
@Test("__cswiftslash_auint8 :: compare exchange weak faillure tests", arguments: Array(0...255))
func testAtomicUInt8CompareExchangeWeakFailure(initialValue: UInt8) {
    // Initialize the atomic uint8_t test harness with a value different from expected
    let atomicValue = AUInt8TestHarness(initialValue)
    
    // Expected value is different from the initial value
    var expected: UInt8
    repeat {
        expected = UInt8.random(in: 0...255)
    } while expected == initialValue
    
    // New value to store
    let newValue: UInt8 = UInt8.random(in: 0...255)
    
    // Perform compare_exchange_weak
    let result = atomicValue.compareExchangeWeak(expected: &expected, desired: newValue)
    
    // Expect the operation to fail
    #expect(result == false)
    
    // Verify that the value was not changed
    let loadedValue = atomicValue.load()
    #expect(loadedValue == initialValue)
}

// Fuzz testing for random atomic operations
@Test("__cswiftslash_auint8 :: fuzz testing atomic operations")
func fuzzTestAtomicUInt8Operations() {
    // Perform the fuzz test 1000 times
    for _ in 0..<1000 {
        // Initialize the atomic uint8_t test harness with a random value
        let atomicValue = AUInt8TestHarness(UInt8.random(in: 0...255))
        
        // Perform random operations
        for _ in 0..<100 {
            let operation = Int.random(in: 0...2)
            switch operation {
            case 0:
                // Store operation
                let value = UInt8.random(in: 0...255)
                atomicValue.store(value)
                let loadedValue = atomicValue.load()
                #expect(loadedValue == value)
            case 1:
                // Load operation
                let _ = atomicValue.load()
            case 2:
                // Compare Exchange Weak operation
                var expected = UInt8.random(in: 0...255)
                let newValue = UInt8.random(in: 0...255)
                // let originalExpected = expected  // Keep a copy of the original expected value
                
                let result = atomicValue.compareExchangeWeak(expected: &expected, desired: newValue)
                let loadedValue = atomicValue.load()
                
                if result {
                    // The exchange was successful; the atomic value should now be newValue
                    #expect(loadedValue == newValue)
                } else {
                    // The exchange failed; expected now contains the current value
                    // Due to spurious failures, the current value might still be equal to originalExpected
                    #expect(loadedValue == expected)
                }
            default:
                break
            }
        }
    }
}

// Concurrent testing of atomic operations using Swift's native concurrency and the test harness
@Test("__cswiftslash_auint8 :: concurrent atomic operations tests")
func concurrentTestAtomicUInt8Operations() async throws {
    // Initialize the atomic uint8_t test harness
    let atomicValue = AUInt8TestHarness(0)
    
    // Create a TaskGroup to perform concurrent operations
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<1000 {
            group.addTask {
                let operation = Int.random(in: 0...2)
                switch operation {
                case 0:
                    // Store operation
                    let value = UInt8.random(in: 0...255)
                    atomicValue.store(value)
                case 1:
                    // Load operation
                    let _ = atomicValue.load()
                case 2:
                    // Compare Exchange Weak operation
                    var expected = UInt8.random(in: 0...255)
                    let newValue = UInt8.random(in: 0...255)
                    _ = atomicValue.compareExchangeWeak(expected: &expected, desired: newValue)
                default:
                    break
                }
            }
        }
    }
    
    // Verify that the final value is within the valid range
    let finalValue = atomicValue.load()
    #expect(finalValue <= 255)
}

// Edge case testing for maximum and minimum values
@Test("__cswiftslash_auint8 :: edge case testing")
func edgeCaseTesting() {
    // Test with maximum value
    let atomicValueMax = AUInt8TestHarness(UInt8.max)
    let loadedMax = atomicValueMax.load()
    #expect(loadedMax == UInt8.max)
    
    // Test with minimum value
    let atomicValueMin = AUInt8TestHarness(UInt8.min)
    let loadedMin = atomicValueMin.load()
    #expect(loadedMin == UInt8.min)
}