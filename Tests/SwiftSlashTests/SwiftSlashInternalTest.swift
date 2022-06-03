import XCTest
@testable import SwiftSlash
@testable import ClibSwiftSlash

final class SwiftSlashInternalTests:XCTestCase {
	func testFDResourceUtilization() {
		var getUsed:Double = 0;
		var getTotal:Double = 0;
		guard getfdlimit(&getUsed, &getTotal) == 0 else {
			XCTFail();
			return
		}
		_ = open("/dev/null", 0);
		var newUsed:Double = 0;
		var newTotal:Double = 0;
		guard getfdlimit(&newUsed, &newTotal) == 0 else {
			XCTFail();
			return
		}
		XCTAssert((getUsed + 1) == newUsed)
	}
	
	func testLineParse() throws {
		let lineTestData = [Data("this is a test of the first line".utf8), Data("".utf8), Data("this is a test of the third line".utf8), Data("line4".utf8)];
		var patternData = Data()
		patternData.append(10)
		patternData.append(13)
		var lineDataMerged = Data(lineTestData.joined(separator:patternData))
		for curThing in lineDataMerged.enumerated() {
			print("\(curThing.0) - \(curThing.1)")
		}
		var buildThings = [Data]()
		var myLP = lineparser();
		withUnsafePointer(to:&buildThings) { unsafePointer in
			patternData.withUnsafeMutableBytes({ patternIn in
				lp_init(&myLP, patternIn.baseAddress, UInt8(patternIn.count), UnsafeMutableRawPointer(mutating:unsafePointer)) { buff, buffSize, usrPtr in
					let intakeData = Data(bytes:buff!, count:buffSize)
					usrPtr!.assumingMemoryBound(to:[Data].self).pointee.append(intakeData)
				}
				lineDataMerged.withUnsafeBytes({ dataIn in
					lp_intake(&myLP, dataIn.baseAddress, dataIn.count);
				})
				lp_close(&myLP);
			})
			guard lineTestData == unsafePointer.pointee else {
				print("\(unsafePointer.pointee)")
				XCTFail()
				return
			}
		}
	}
	
	func testQueue() throws {
		var et = et_alloc()!;
		et_init(et);
		let newPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true);
		et_r_register(et, newPipe.reading) { fh, readSize, isClosed in
			print("attempting to read \(readSize) bytes")
		}
		let writeString = "hello this is a test\n"
		write(newPipe.writing, writeString, writeString.count);
		sleep(5);
		print("trying to close")
		et_close(et);
		print("close completed")
	}
}
