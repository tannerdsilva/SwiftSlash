extension Data {
	internal func cutLines(flush:Bool) -> (lines:[Data]?, cut:Data.Index) {
		//itterate to find the line breaks
		var lf = Set<Range<Self.Index>>()
		var lfLast:Self.Index? = nil
		var crLast:Self.Index? = nil
		var cr = Set<Range<Self.Index>>()
		var crlf = Set<Range<Self.Index>>()
		var suspectedLineCount:UInt64 = 0
		
		//main parsing loop
		for (n, curByte) in enumerated() {
			switch curByte {
				case 10: //lf
					let lb:Data.Index
					if let hasLb = lfLast {
						lb = hasLb.advanced(by: 1)
					} else {
						lb = startIndex
					}
					
					//was last character cr?
					if (crLast != nil && crLast! == n-1) {
						crlf.update(with:lb..<crLast!)
					} else {
						suspectedLineCount += 1
					}

					lf.update(with:lb..<n)
					lfLast = n
				case 13: //cr
					let lb:Data.Index
					if let hasLb = crLast {
						lb = hasLb.advanced(by: 1)
					} else {
						lb = startIndex
					}

					cr.update(with:lb..<n)
					crLast = n
					suspectedLineCount += 1
				default:
				break;
			}
		}
		
		//if there were no lines, return early
		if suspectedLineCount == 0 { 
			return (lines:nil, cut:self.startIndex)
		}
		
		let crlfTotal = crlf.count
		let suspectedLineCountAsDouble = Double(suspectedLineCount)
		var lfTotal = lf.count - crlfTotal
		if (lfTotal < 0) {
			lfTotal = 0
		}
		var crTotal = cr.count - crlfTotal
		if (crTotal < 0) {
			crTotal = 0
		}
	
		func returnValueForLines(_ linesIn:[Range<Self.Index>]) -> (lines:[Data]?, cut:Self.Index) {
			if linesIn.count <= 1 && flush == false {
				return (lines:nil, cut:startIndex)
			} else if flush == false {
				var pickLines = linesIn
				let lastLine = pickLines.removeLast()
                return (lines:pickLines.map { self[$0] }, cut:lastLine.lowerBound)
            } else {
                return (lines:linesIn.map { self[$0] }, cut:endIndex)
            }
		}
		
		let lfPercent:Double = Double(lfTotal)/suspectedLineCountAsDouble
		let crPercent:Double = Double(crTotal)/suspectedLineCountAsDouble
		let crlfPercent:Double = Double(crlfTotal)/suspectedLineCountAsDouble

		if (crlfPercent > crPercent && crlfPercent > lfPercent) {
			//CR-LF MODE
			
			//add the final line
			var lb:Self.Index
			if let hasLb = lfLast {
				lb = hasLb.advanced(by:1)
			} else {
				lb = startIndex
			}
			if lb < endIndex {
				crlf.update(with:lb..<endIndex)
			}
			
			return returnValueForLines(crlf.sorted(by: { $0.lowerBound < $1.lowerBound }))
			
			//parse the line indexes and return
		} else if (lfPercent > crlfPercent && lfPercent > crPercent) {
			//LF MODE
			
			//add the final line
			var lb:Self.Index
			if let hasLb = lfLast {
				lb = hasLb.advanced(by:1)
			} else {
				lb = startIndex
			}
			if lb < endIndex {
				lf.update(with:lb..<endIndex)
			}
			
			return returnValueForLines(lf.sorted(by: { $0.lowerBound < $1.lowerBound }))
		} else {
			//CR MODE
			
			//add the final line
			var lb:Self.Index
			if let hasLb = crLast {
				lb = hasLb.advanced(by: 1)
			} else {
				lb = startIndex
			}
			if lb < endIndex {
				cr.update(with:lb..<endIndex)
			}
			
			return returnValueForLines(cr.sorted(by: { $0.lowerBound < $1.lowerBound }))
		}
	}
}