// Package yahoo adapts a dated COMEX futures contract, never a CFD or continuous symbol.
package yahoo

import (
	"context"
	"encoding/json"
	"fmt"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	"io"
	"math"
	"net/http"
	"net/url"
	"sync"
	"time"
)

type Client struct {
	HTTP     *http.Client
	Symbol   string
	FX       ports.GoldQuoteSource
	mu       sync.Mutex
	cached   *chartResult
	cachedAt time.Time
}
type chartResult struct {
	sessionOpen float64
	Meta        struct {
		Symbol   string  `json:"symbol"`
		Currency string  `json:"currency"`
		Exchange string  `json:"exchangeName"`
		Kind     string  `json:"instrumentType"`
		Time     int64   `json:"regularMarketTime"`
		Price    float64 `json:"regularMarketPrice"`
		High     float64 `json:"regularMarketDayHigh"`
		Low      float64 `json:"regularMarketDayLow"`
		Previous float64 `json:"previousClose"`
	} `json:"meta"`
	Times      []int64 `json:"timestamp"`
	Indicators struct {
		Quotes []struct{ Open, High, Low, Close []*float64 } `json:"quote"`
	} `json:"indicators"`
}

func (c *Client) fetch(ctx context.Context, interval, span string) (*chartResult, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://query1.finance.yahoo.com/v8/finance/chart/"+url.PathEscape(c.Symbol)+"?interval="+interval+"&range="+span, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0")
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("Yahoo HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, err
	}
	return parseChart(body, c.Symbol)
}
func (c *Client) recent(ctx context.Context) (*chartResult, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cached != nil && time.Since(c.cachedAt) < 15*time.Second {
		return c.cached, nil
	}
	p, err := c.fetch(ctx, "1m", "1d")
	if err != nil {
		return nil, err
	}
	daily, err := c.fetch(ctx, "1d", "5d")
	if err != nil {
		return nil, err
	}
	zone, err := time.LoadLocation("America/New_York")
	if err != nil {
		return nil, err
	}
	day := time.Unix(p.Meta.Time, 0).In(zone).Format("2006-01-02")
	values := daily.Indicators.Quotes[0].Open
	for i, stamp := range daily.Times {
		if i < len(values) && values[i] != nil && positive(*values[i]) && time.Unix(stamp, 0).In(zone).Format("2006-01-02") == day {
			p.sessionOpen = *values[i]
		}
	}
	if !positive(p.sessionOpen) {
		return nil, fmt.Errorf("Yahoo missing matching session open")
	}
	c.cached = p
	c.cachedAt = time.Now()
	return p, nil
}
func parseChart(body []byte, symbol string) (*chartResult, error) {
	var envelope struct {
		Chart struct {
			Result []chartResult   `json:"result"`
			Error  json.RawMessage `json:"error"`
		} `json:"chart"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil {
		return nil, err
	}
	if len(envelope.Chart.Result) != 1 {
		return nil, fmt.Errorf("Yahoo missing chart")
	}
	p := envelope.Chart.Result[0]
	if p.Meta.Symbol != symbol || p.Meta.Currency != "USD" || p.Meta.Exchange != "CMX" || p.Meta.Kind != "FUTURE" {
		return nil, fmt.Errorf("Yahoo contract identity mismatch")
	}
	if len(p.Indicators.Quotes) != 1 {
		return nil, fmt.Errorf("Yahoo missing candles")
	}
	return &p, nil
}
func positive(p float64) bool { return p > 0 && !math.IsNaN(p) && !math.IsInf(p, 0) }
func (p *chartResult) quote() (domain.GoldQuote, error) {
	m := p.Meta
	if !positive(m.Price) || !positive(m.Previous) || m.Time <= 0 {
		return domain.GoldQuote{}, fmt.Errorf("Yahoo invalid quote")
	}
	open := p.sessionOpen
	if !positive(open) || !positive(m.High) || !positive(m.Low) {
		return domain.GoldQuote{}, fmt.Errorf("Yahoo missing OHLC")
	}
	return domain.GoldQuote{Symbol: m.Symbol, Currency: "USD", SourceDelaySeconds: 1800, Price: m.Price, PrevClose: m.Previous, Open: open, High: m.High, Low: m.Low, AsOf: time.Unix(m.Time, 0).In(time.FixedZone("CST", 8*3600))}, nil
}
func (c *Client) FetchGoldQuote(ctx context.Context) (domain.GoldQuote, error) {
	p, err := c.recent(ctx)
	if err != nil {
		return domain.GoldQuote{}, err
	}
	q, err := p.quote()
	if err != nil {
		return q, err
	}
	if c.FX != nil {
		fx, e := c.FX.FetchGoldQuote(ctx)
		if e == nil {
			q.USDCNY = fx.USDCNY
		}
	}
	return q, nil
}
func (p *chartResult) minutes() []domain.IntradayPoint {
	points := []domain.IntradayPoint{}
	values := p.Indicators.Quotes[0].Close
	for i, stamp := range p.Times {
		if i >= len(values) || values[i] == nil || !positive(*values[i]) || stamp > p.Meta.Time {
			continue
		}
		points = append(points, domain.IntradayPoint{Time: time.Unix(stamp, 0).In(time.FixedZone("CST", 8*3600)), Price: *values[i]})
	}
	return points
}
func (c *Client) FetchGoldIntraday(ctx context.Context) ([]domain.IntradayPoint, error) {
	p, e := c.recent(ctx)
	if e != nil {
		return nil, e
	}
	return p.minutes(), nil
}
func (c *Client) FetchGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error) {
	p, e := c.fetch(ctx, "1d", "max")
	if e != nil {
		return nil, e
	}
	zone, e := time.LoadLocation("America/New_York")
	if e != nil {
		return nil, e
	}
	v := p.Indicators.Quotes[0]
	bars := []domain.DailyBar{}
	for i, stamp := range p.Times {
		if i >= len(v.Open) || i >= len(v.Close) || i >= len(v.High) || i >= len(v.Low) || v.Open[i] == nil || v.Close[i] == nil || v.High[i] == nil || v.Low[i] == nil {
			continue
		}
		o, h, l, cl := *v.Open[i], *v.High[i], *v.Low[i], *v.Close[i]
		if !positive(o) || !positive(h) || !positive(l) || !positive(cl) || l > h || o < l || o > h || cl < l || cl > h {
			continue
		}
		t := time.Unix(stamp, 0).In(zone)
		day := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, zone)
		bars = append(bars, domain.DailyBar{Date: day, Open: o, High: h, Low: l, Close: cl})
	}
	if len(bars) == 0 {
		return nil, fmt.Errorf("Yahoo no valid daily candles")
	}
	return bars, nil
}
