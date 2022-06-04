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
		var buildThings = [Data]()
		var myLP = lineparser();
		withUnsafePointer(to:&buildThings) { unsafePointer in
			patternData.withUnsafeMutableBytes({ patternIn in
				lp_init(&myLP, patternIn.baseAddress!.bindMemory(to:UInt8.self, capacity:patternIn.count), UInt8(patternIn.count), UnsafeMutableRawPointer(mutating:unsafePointer)) { buff, buffSize, usrPtr in
					let intakeData = Data(bytes:buff!, count:buffSize)
					usrPtr!.assumingMemoryBound(to:[Data].self).pointee.append(intakeData)
				}
				lineDataMerged.withUnsafeBytes({ dataIn in
					lp_intake(&myLP, dataIn.baseAddress!.bindMemory(to:UInt8.self, capacity:patternIn.count), dataIn.count);
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
		print("registering \(newPipe.reading)");
		
		var readerinfo = readerinfo_t(fh:newPipe.reading, handler:{ rh, readbuff, readSize, isClosed in
			let asData = Data(bytes:readbuff!, count:readSize)
			let asString = String(data:asData, encoding:.utf8)
			print("fool \(readSize) \(isClosed)\n\t ->\(asString)")
		})
		let regResult = et_r_register(et, &readerinfo)
		print("register result: \(regResult)")
		for i in 0..<10 {
			let writeString = "hello this is a test\n"
			write(newPipe.writing, writeString, writeString.count);
			sleep(1);
		}
		close(newPipe.writing);
		sleep(5);
		print("trying to close")
		et_close(et);
		print("close completed")
	}
}
