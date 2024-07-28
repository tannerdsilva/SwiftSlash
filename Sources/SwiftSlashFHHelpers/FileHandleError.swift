public enum FileHandleError:Swift.Error {
	case pollingError;
	case readAllocationError;
	
	case pipeOpenError;
	
	case fcntlError;
	
	case error_unknown;
	
	case error_again;
	case error_wouldblock;
	case error_bad_fh;
	case error_interrupted;
	case error_invalid;
	case error_io;
	case error_nospace;
	
	case error_pipe;
}