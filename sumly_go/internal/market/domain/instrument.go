package domain

import "time"

// Instrument identifies the economic product independently of the data vendor.
// Contract remains empty unless an actual dated futures contract is verified.
type Instrument struct {
	DelaySeconds int
	ID           string
	Name         string
	Symbol       string
	Kind         string
	Currency     string
	Unit         string
	QuoteSource  string
	DailySource  string
	Exchange     string
	Contract     string
}

type GoldWindow struct {
	Points          []RealtimePoint
	IntervalSeconds int
	WindowSeconds   int
	Start           time.Time
	End             time.Time
}
