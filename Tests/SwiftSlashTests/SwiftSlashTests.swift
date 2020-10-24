import XCTest
@testable import SwiftSlash

extension String {
	public static func random(length:Int = 32) -> String {
		let base = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
		let baseLength = base.count
		var randomString = ""
		for _ in 0..<length {
			let randomIndex = Int.random(in:0..<baseLength)
			randomString.append(base[base.index(base.startIndex, offsetBy:randomIndex)])
		}
		return randomString
	}
}

extension FileManager {
     public func mktemp(clashVerify:Bool = false) throws -> URL {
    	let temporaryDirectory = try FileManager.default.temporaryDirectory
    	let dirName = String.random(length:Int.random(in:10..<24))
    	let targetURL = temporaryDirectory.appendingPathComponent(dirName, isDirectory:true)
    	if clashVerify {
    		if try FileManager.default.fileExists(atPath:targetURL.path) == true {
    			throw CommandError.temporaryDirectoryNameConflict
    		}
    	}
		try FileManager.default.createDirectory(at:targetURL, withIntermediateDirectories:false)
		return targetURL
    }
}

final class SwiftSlashTests: XCTestCase {
    func testExample() {
		let buildExecutableDirectory = FileManager.default.mktemp()
		
        XCTAssertEqual(SwiftSlash().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}

final class DataChannelMonitorTests: XCTestCase {
	
	func outboundChannelTest() {
		let newPipe = PosixPipe(nonblockingReads:true, nonblockingWrites:true)
		let outboundTerminationExpectation = XCTestExpectation(description:"Expecting OutboundDataChannel to fire its termination handler when the reading end is closed")
		let channelMonitor = DataChannelMonitor()
		
		//test with some initial data to pass on initialization
		let initialData = "HELLO THIS IS INITIAL DATA".data(encoding:.utf8)!
		let outChannel = channelMonitor.registerOutboundDataChannel(fh:newPipe.writing, terminationHandler:{ outboundTerminationExpectation.fufill() })
		
		var capturedData = [String]()
		let readChannel = channelMnitor.registerInboundDataChannel(fh:newPipe.reading, mode:.lf, dataHandler: { someData in
			if let hasString = String(data:someData, encoding:.utf8) {
				capturedData.append(hasString)
			}
		}, terminationHandler: { return })
	}
	
	static var allTests = [("processWriteTest", processWriteTest)]
}