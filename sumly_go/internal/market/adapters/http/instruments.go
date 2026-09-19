package markethttp

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	shared "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	"github.com/gin-gonic/gin"
	"time"
)

type InstrumentsUseCase interface {
	Catalog() []domain.Instrument
	Quote(context.Context, string) (domain.Instrument, domain.GoldQuote, error)
	Daily(context.Context, string) (domain.Instrument, []domain.DailyBar, error)
	Realtime(context.Context, string) (domain.Instrument, domain.GoldWindow, error)
}
type InstrumentsHandler struct{ service InstrumentsUseCase }

func NewInstrumentsHandler(s InstrumentsUseCase) *InstrumentsHandler { return &InstrumentsHandler{s} }

type InstrumentDTO struct {
	DelaySeconds int    `json:"delay_seconds"`
	ID           string `json:"id"`
	Name         string `json:"name"`
	Symbol       string `json:"symbol"`
	Kind         string `json:"kind"`
	Currency     string `json:"currency"`
	Unit         string `json:"unit"`
	QuoteSource  string `json:"quote_source"`
	DailySource  string `json:"daily_source"`
	Exchange     string `json:"exchange,omitempty"`
	Contract     string `json:"contract,omitempty"`
}

func instrumentDTO(i domain.Instrument) InstrumentDTO {
	return InstrumentDTO{i.DelaySeconds, i.ID, i.Name, i.Symbol, i.Kind, i.Currency, i.Unit, i.QuoteSource, i.DailySource, i.Exchange, i.Contract}
}
func (h *InstrumentsHandler) RegisterPublicRoutes(group *gin.RouterGroup) {
	group.GET("/market/gold/instruments", func(c *gin.Context) {
		list := make([]InstrumentDTO, 0)
		for _, i := range h.service.Catalog() {
			list = append(list, instrumentDTO(i))
		}
		shared.WriteSuccess(c, gin.H{"instruments": list})
	})
	group.GET("/market/gold/instruments/:instrument/quote", h.Quote)
	group.GET("/market/gold/instruments/:instrument/daily", h.Daily)
	group.GET("/market/gold/instruments/:instrument/realtime", h.Realtime)
}
func (h *InstrumentsHandler) Quote(c *gin.Context) {
	i, q, e := h.service.Quote(c.Request.Context(), c.Param("instrument"))
	if e != nil {
		shared.WriteError(c, e)
		return
	}
	shared.WriteSuccess(c, struct {
		Instrument InstrumentDTO `json:"instrument"`
		GoldQuoteResponse
	}{instrumentDTO(i), GoldQuoteResponse{Symbol: q.Symbol, Price: q.Price, Open: q.Open, High: q.High, Low: q.Low, PrevClose: q.PrevClose, Change: q.Change(), ChangePercent: q.ChangePercent(), USDCNY: q.USDCNY, CNYPerGram: q.CNYPerGram(), AsOf: q.AsOf.Format(time.RFC3339)}})
}
func (h *InstrumentsHandler) Daily(c *gin.Context) {
	i, bars, e := h.service.Daily(c.Request.Context(), c.Param("instrument"))
	if e != nil {
		shared.WriteError(c, e)
		return
	}
	list := make([]GoldDailyBarResponse, 0, len(bars))
	for _, b := range bars {
		list = append(list, GoldDailyBarResponse{Date: b.Date.Format("2006-01-02"), Open: b.Open, High: b.High, Low: b.Low, Close: b.Close})
	}
	shared.WriteSuccess(c, gin.H{"instrument": instrumentDTO(i), "unit": i.Unit, "bars": list})
}
func (h *InstrumentsHandler) Realtime(c *gin.Context) {
	i, window, e := h.service.Realtime(c.Request.Context(), c.Param("instrument"))
	if e != nil {
		shared.WriteError(c, e)
		return
	}
	type pointDTO struct {
		Time       string  `json:"time"`
		SourceTime string  `json:"source_time"`
		Price      float64 `json:"price"`
	}
	list := make([]pointDTO, 0, len(window.Points))
	for _, p := range window.Points {
		list = append(list, pointDTO{p.Time.Format(time.RFC3339), p.SourceTime.Format(time.RFC3339), p.Price})
	}
	var start, end string
	if !window.End.IsZero() {
		start = window.Start.Format(time.RFC3339)
		end = window.End.Format(time.RFC3339)
	}
	shared.WriteSuccess(c, gin.H{"instrument": instrumentDTO(i), "unit": i.Unit, "interval_seconds": window.IntervalSeconds, "window_seconds": window.WindowSeconds, "window_start": start, "window_end": end, "points": list})
}
