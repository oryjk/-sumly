package markethttp

import (
	"context"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	sharedhttpapi "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	"github.com/gin-gonic/gin"
)

// GoldMarketUseCase 由 application 层实现；行情是公开数据，无需登录。
type GoldMarketUseCase interface {
	GetGoldRealtime(context.Context) ([]domain.RealtimePoint, int, error)
	GetGoldIntraday(ctx context.Context) ([]domain.IntradayPoint, error)
	GetGoldQuote(ctx context.Context) (domain.GoldQuote, error)
	GetGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error)
}

type Handler struct {
	goldMarket GoldMarketUseCase
}

func NewHandler(goldMarket GoldMarketUseCase) *Handler {
	return &Handler{goldMarket: goldMarket}
}

type GoldQuoteResponse struct {
	Symbol        string  `json:"symbol"`
	Price         float64 `json:"price"`
	Open          float64 `json:"open"`
	High          float64 `json:"high"`
	Low           float64 `json:"low"`
	PrevClose     float64 `json:"prev_close"`
	Change        float64 `json:"change"`
	ChangePercent float64 `json:"change_percent"`
	USDCNY        float64 `json:"usd_cny"`      // 美元兑人民币中间价（买卖均值）；0 表示不可用
	CNYPerGram    float64 `json:"cny_per_gram"` // 每克人民币价；0 表示不可用
	AsOf          string  `json:"as_of"`        // RFC3339，北京时间
}

type GoldDailyBarResponse struct {
	Date  string  `json:"date"` // yyyy-MM-dd（北京时间交易日）
	Open  float64 `json:"open"`
	High  float64 `json:"high"`
	Low   float64 `json:"low"`
	Close float64 `json:"close"`
}

type GoldDailyResponse struct {
	Symbol string                 `json:"symbol"`
	Bars   []GoldDailyBarResponse `json:"bars"`
}

func (h *Handler) GoldQuote(c *gin.Context) {
	quote, err := h.goldMarket.GetGoldQuote(c.Request.Context())
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	sharedhttpapi.WriteSuccess(c, GoldQuoteResponse{
		Symbol:        quote.Symbol,
		Price:         quote.Price,
		Open:          quote.Open,
		High:          quote.High,
		Low:           quote.Low,
		PrevClose:     quote.PrevClose,
		Change:        quote.Change(),
		ChangePercent: quote.ChangePercent(),
		USDCNY:        quote.USDCNY,
		CNYPerGram:    quote.CNYPerGram(),
		AsOf:          quote.AsOf.Format(time.RFC3339),
	})
}

func (h *Handler) GoldDaily(c *gin.Context) {
	bars, err := h.goldMarket.GetGoldDailyKLines(c.Request.Context())
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	response := GoldDailyResponse{Symbol: "XAUUSD", Bars: make([]GoldDailyBarResponse, 0, len(bars))}
	for _, bar := range bars {
		response.Bars = append(response.Bars, GoldDailyBarResponse{
			Date:  bar.Date.Format("2006-01-02"),
			Open:  bar.Open,
			High:  bar.High,
			Low:   bar.Low,
			Close: bar.Close,
		})
	}
	sharedhttpapi.WriteSuccess(c, response)
}

func (h *Handler) RegisterPublicRoutes(group *gin.RouterGroup) {
	group.GET("/market/gold/quote", h.GoldQuote)
	group.GET("/market/gold/intraday", h.GoldIntraday)
	group.GET("/market/gold/realtime", h.GoldRealtime)
	group.GET("/market/gold/daily", h.GoldDaily)
}

func (h *Handler) GoldIntraday(c *gin.Context) {
	points, err := h.goldMarket.GetGoldIntraday(c.Request.Context())
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	type pointResponse struct {
		Time  string  `json:"time"`
		Price float64 `json:"price"`
	}
	response := struct {
		Symbol string          `json:"symbol"`
		Points []pointResponse `json:"points"`
	}{Symbol: "XAUUSD", Points: make([]pointResponse, 0, len(points))}
	for _, point := range points {
		response.Points = append(response.Points, pointResponse{Time: point.Time.Format(time.RFC3339), Price: point.Price})
	}
	sharedhttpapi.WriteSuccess(c, response)
}

// GoldRealtime 返回最后可用窗口，interval_seconds 标明实际五秒采样或分钟回退。
func (h *Handler) GoldRealtime(c *gin.Context) {
	points, interval, err := h.goldMarket.GetGoldRealtime(c.Request.Context())
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	type pointResponse struct {
		Time       string  `json:"time"`
		SourceTime string  `json:"source_time"`
		Price      float64 `json:"price"`
	}
	response := struct {
		Symbol          string          `json:"symbol"`
		Unit            string          `json:"unit"`
		IntervalSeconds int             `json:"interval_seconds"`
		WindowSeconds   int             `json:"window_seconds"`
		Points          []pointResponse `json:"points"`
	}{Symbol: "XAUUSD", Unit: "CNY/g", IntervalSeconds: interval, WindowSeconds: 1200, Points: make([]pointResponse, 0)}
	for _, p := range points {
		response.Points = append(response.Points, pointResponse{Time: p.Time.Format(time.RFC3339), SourceTime: p.SourceTime.Format(time.RFC3339), Price: p.Price})
	}
	sharedhttpapi.WriteSuccess(c, response)
}
