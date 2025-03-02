import SwiftSlashFIFO

/// utility structure used to set up the event trigger.
public struct EventTriggerSetup<HP>:Sendable where HP:Sendable {
	// the primitive handle type that is used to handle the event trigger.
	internal let handle:HP
	// the FIFO that is used to pass registrations to the event trigger to the pthread that is handling the event trigger.
	internal let registersIn:FIFO<Register, Never>
}
