package domain

import "time"

// GoldHistoryPoint is a nominal USD/troy-ounce observation, not an OHLC bar.
type GoldHistoryPoint struct {
	Date        time.Time
	Price       float64
	Granularity string
	Source      string
}
