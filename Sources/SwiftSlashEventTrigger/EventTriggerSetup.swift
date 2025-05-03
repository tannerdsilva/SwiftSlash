/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import SwiftSlashFIFO
import SwiftSlashFHHelpers

/// utility structure used to set up the event trigger.
public struct EventTriggerSetup<HP, DataChannelChildReadError, DataChannelChildWriteError>:Sendable where HP:Sendable, DataChannelChildReadError:Swift.Error, DataChannelChildWriteError:Swift.Error {
	// the primitive handle type that is used to handle the event trigger.
	internal let handle:HP
	// the FIFO that is used to pass registrations to the event trigger to the pthread that is handling the event trigger.
	internal let registersIn:FIFO<(Int32, Register<DataChannelChildReadError, DataChannelChildWriteError>?), Never>
	// the cancellation pipe that is registered with the event trigger to assist in shutting down the event trigger when it needs to be cancelled.
	internal let cancelPipe:PosixPipe
}
