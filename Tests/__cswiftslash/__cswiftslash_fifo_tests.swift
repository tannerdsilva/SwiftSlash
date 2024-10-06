import Testing

import __cswiftslash_fifo

// MARK: - FIFO Harness Class

/// A Swift wrapper around the C FIFO implementation.
/// This class is marked as `@unchecked Sendable` to allow concurrency optimizations.
fileprivate final class FIFOHarness: @unchecked Sendable {
    // Pointer to the C FIFO structure
    fileprivate let fifoPtr: UnsafeMutablePointer<_cswiftslash_fifo_linkpair_t>
    
    /// Initializes a new FIFO instance.
    fileprivate init() {
        self.fifoPtr = _cswiftslash_fifo_init(nil)
    }
    
    /// Passes data into the FIFO.
    @discardableResult
    fileprivate func pass(_ data: UnsafeMutableRawPointer) -> Int8 {
        return _cswiftslash_fifo_pass(self.fifoPtr, data)
    }
    
    /// Consumes data from the FIFO in a non-blocking manner.
    fileprivate func consumeNonBlocking() -> (_cswiftslash_fifo_consume_result_t, UnsafeMutableRawPointer?) {
        var consumedData: UnsafeMutableRawPointer?
        let result = _cswiftslash_fifo_consume_nonblocking(self.fifoPtr, &consumedData)
        return (result, consumedData)
    }
    
    /// Consumes data from the FIFO in a blocking manner.
    fileprivate func consumeBlocking() -> (_cswiftslash_fifo_consume_result_t, UnsafeMutableRawPointer?) {
        var consumedData: UnsafeMutableRawPointer?
        let result = _cswiftslash_fifo_consume_blocking(self.fifoPtr, &consumedData)
        return (result, consumedData)
    }
    
    /// Caps the FIFO with a final element.
    fileprivate func passCap(_ capData: UnsafeMutableRawPointer?) -> Bool {
        return _cswiftslash_fifo_pass_cap(self.fifoPtr, capData)
    }
    
    /// Sets the maximum number of elements in the FIFO.
    fileprivate func setMaxElements(_ maxElements: size_t) -> Bool {
        return _cswiftslash_fifo_set_max_elements(self.fifoPtr, maxElements)
    }
    
    /// Closes the FIFO and optionally deallocates unconsumed elements.
    fileprivate func close(deallocator: _cswiftslash_fifo_link_ptr_consume_f? = nil) -> UnsafeMutableRawPointer? {
        return _cswiftslash_fifo_close(self.fifoPtr, deallocator)
    }
    
    deinit {
        _ = self.close()
    }
}

// MARK: - Test Cases

@Test("__cswiftslash_fifo :: initialization tests")
func testFIFOInitialization() {
    let fifo = FIFOHarness()
    
    // Since we cannot access internal variables, we'll check expected behavior
    
    // Attempt to consume from the empty FIFO
    let (consumeResult, consumedData) = fifo.consumeNonBlocking()
    #expect(consumeResult == FIFO_CONSUME_WOULDBLOCK)
    #expect(consumedData == nil)
    
    // Pass data and ensure it succeeds
    let data = UnsafeMutableRawPointer(bitPattern: 0x1)!
    let passResult = fifo.pass(data)
    #expect(passResult == 0)
    
    // Consume the data back
    let (consumeResult2, consumedData2) = fifo.consumeNonBlocking()
    #expect(consumeResult2 == FIFO_CONSUME_RESULT)
    #expect(consumedData2 == data)
}

@Test("__cswiftslash_fifo :: pass and consume single element")
func testPassAndConsumeSingleElement() {
    let fifo = FIFOHarness()
    
    let data = UnsafeMutableRawPointer(bitPattern: 0xdeadbeef)!
    let passResult = fifo.pass(data)
    #expect(passResult == 0)
    
    let (consumeResult, consumedData) = fifo.consumeNonBlocking()
    #expect(consumeResult == FIFO_CONSUME_RESULT)
    #expect(consumedData == data)
}

@Test("__cswiftslash_fifo :: consume from empty FIFO")
func testConsumeFromEmptyFIFO() {
    let fifo = FIFOHarness()
    
    let (consumeResult, consumedData) = fifo.consumeNonBlocking()
    #expect(consumeResult == FIFO_CONSUME_WOULDBLOCK)
    #expect(consumedData == nil)
}

@Test("__cswiftslash_fifo :: pass and consume multiple elements")
func testFIFOCap() {
    let fifo = FIFOHarness()
    
    let capData = UnsafeMutableRawPointer(bitPattern: 0xfeedface)!
    let capResult = fifo.passCap(capData)
    #expect(capResult == true)
    
    // Attempt to pass data after cap
    let data = UnsafeMutableRawPointer(bitPattern: 0xcafebabe)!
    let passResult = fifo.pass(data)
    #expect(passResult == -1)
    
    // Consume cap data
    let (consumeResult, consumedData) = fifo.consumeNonBlocking()
    #expect(consumeResult == FIFO_CONSUME_CAP)
    #expect(consumedData == capData)
    
    // Attempt to consume again
    let (consumeResult2, consumedData2) = fifo.consumeNonBlocking()
    #expect(consumeResult2 == FIFO_CONSUME_CAP)
    #expect(consumedData2 == capData)
}

@Test("__cswiftslash_fifo :: set max elements")
func testSetMaxElements() {
    let fifo = FIFOHarness()
    
    let setResult = fifo.setMaxElements(2)
    #expect(setResult == true)
    
    // Pass two elements
    let data1 = UnsafeMutableRawPointer(bitPattern: 0x1)!
    let data2 = UnsafeMutableRawPointer(bitPattern: 0x2)!
    #expect(fifo.pass(data1) == 0)
    #expect(fifo.pass(data2) == 0)
    
    // Attempt to pass a third element
    let data3 = UnsafeMutableRawPointer(bitPattern: 0x3)!
    #expect(fifo.pass(data3) == -2)
    
    // Consume one element
    let (consumeResult, consumedData) = fifo.consumeNonBlocking()
    #expect(consumeResult == FIFO_CONSUME_RESULT)
    #expect(consumedData == data1)
    
    // Now passing should succeed
    #expect(fifo.pass(data3) == 0)
}

@Test("__cswiftslash_fifo :: non-blocking vs blocking consume")
func testNonBlockingVsBlockingConsume() async throws {
    let fifo = FIFOHarness()
    
    // Start a consumer task
    let consumer = Task {
        let (consumeResult, consumedData) = fifo.consumeBlocking()
        #expect(consumeResult == FIFO_CONSUME_RESULT)
        #expect(consumedData == UnsafeMutableRawPointer(bitPattern: 0xabc)!)
    }
    
    // Simulate delay
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Pass data
    let data = UnsafeMutableRawPointer(bitPattern: 0xabc)!
    #expect(fifo.pass(data) == 0)
    
    // Wait for consumer to finish
    await consumer.value
}

@Test("__cswiftslash_fifo :: fuzz testing FIFO")
func testFuzzTestingFIFO() async {
    let fifo = FIFOHarness()
    
    let iterations = 10000
    
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<iterations {
            group.addTask {
                let action = Int.random(in: 0...1)
                if action == 0 {
                    // Producer
                    let data = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
                    data.storeBytes(of: UInt8.random(in: 0...255), as: UInt8.self)
                    _ = fifo.pass(data)
                } else {
                    // Consumer
                    let (consumeResult, consumedData) = fifo.consumeNonBlocking()
                    if consumeResult == FIFO_CONSUME_RESULT, let data = consumedData {
                        data.deallocate()
                    }
                }
            }
        }
    }
    
    // Clean up any remaining data
    while true {
        let (consumeResult, consumedData) = fifo.consumeNonBlocking()
        if consumeResult == FIFO_CONSUME_RESULT, let data = consumedData {
            data.deallocate()
        } else {
            break
        }
    }
}

@Test("__cswiftslash_fifo :: blocking consume with cap")
func testBlockingConsumeWithCap() async {
    let fifo = FIFOHarness()
    
    // Cap the FIFO
    let capData = UnsafeMutableRawPointer(bitPattern: 0xfeed)!
    #expect(fifo.passCap(capData) == true)
    
    // Start a consumer task
    let consumer = Task {
        let (consumeResult, consumedData) = fifo.consumeBlocking()
        #expect(consumeResult == FIFO_CONSUME_CAP)
        #expect(consumedData == capData)
    }
    
    // Wait for consumer to finish
    await consumer.value
}

@Test("__cswiftslash_fifo :: set max elements to zero")
func testSetMaxElementsToZero() {
    let fifo = FIFOHarness()
    
    #expect(fifo.setMaxElements(0) == true)
    
    // Attempt to pass data
    let data = UnsafeMutableRawPointer(bitPattern: 0x1)!
    let passResult = fifo.pass(data)
    #expect(passResult == -2) // Max elements reached
}