/* LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_posix_helpers

public enum FileHandleError:Swift.Error {
	case pollingError;
	case readAllocationError;
	
	case pipeOpenError;
	
	case fcntlError;
	
	case error_unknown(Int32);
	
	case error_again;
	case error_wouldblock;
	case error_bad_fh;
	case error_interrupted;
	case error_invalid;
	case error_io;
	case error_nospace;
	case error_quota;
	
	case error_pipe;

	public init(errno:Int32) {
		switch errno {
			case EAGAIN:
				self = .error_again;
			case EWOULDBLOCK:
				self = .error_wouldblock;
			case EBADF:
				self = .error_bad_fh;
			case EINTR:
				self = .error_interrupted;
			case EINVAL:
				self = .error_invalid;
			case EIO:
				self = .error_io;
			case ENOSPC:
				self = .error_nospace;
			case EDQUOT:
				self = .error_quota;
			default:
				self = .error_unknown(errno)
		}
	}
}