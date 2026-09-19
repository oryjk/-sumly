package application

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

type InstrumentMarket struct {
	Instrument domain.Instrument
	Service    *GoldMarketService
}
type Instruments struct{ markets []InstrumentMarket }

func NewInstruments(markets []InstrumentMarket) *Instruments {
	return &Instruments{append([]InstrumentMarket(nil), markets...)}
}
func (s *Instruments) Catalog() []domain.Instrument {
	result := make([]domain.Instrument, 0, len(s.markets))
	for _, m := range s.markets {
		result = append(result, m.Instrument)
	}
	return result
}
func (s *Instruments) lookup(id string) (InstrumentMarket, error) {
	for _, m := range s.markets {
		if m.Instrument.ID == id {
			return m, nil
		}
	}
	return InstrumentMarket{}, sharederror.New(sharederror.KindNotFound, "行情品种不存在")
}
func (s *Instruments) Quote(ctx context.Context, id string) (domain.Instrument, domain.GoldQuote, error) {
	m, e := s.lookup(id)
	if e != nil {
		return domain.Instrument{}, domain.GoldQuote{}, e
	}
	q, e := m.Service.GetGoldQuote(ctx)
	return m.Instrument, q, e
}
func (s *Instruments) Daily(ctx context.Context, id string) (domain.Instrument, []domain.DailyBar, error) {
	m, e := s.lookup(id)
	if e != nil {
		return domain.Instrument{}, nil, e
	}
	p, e := m.Service.GetGoldDailyKLines(ctx)
	return m.Instrument, p, e
}
func (s *Instruments) Realtime(ctx context.Context, id string) (domain.Instrument, domain.GoldWindow, error) {
	m, e := s.lookup(id)
	if e != nil {
		return domain.Instrument{}, domain.GoldWindow{}, e
	}
	points, interval, e := m.Service.GetGoldRealtime(ctx)
	window := domain.GoldWindow{Points: points, IntervalSeconds: interval, WindowSeconds: int(RealtimeWindow.Seconds())}
	if len(points) > 0 {
		window.End = points[len(points)-1].Time
		window.Start = window.End.Add(-RealtimeWindow)
	}
	return m.Instrument, window, e
}
