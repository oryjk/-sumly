package sina

import (
	"context"
	"fmt"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"math"
	"strconv"
	"strings"
	"time"
)

// InstrumentClient 仅接收 bootstrap 中的固定配置，不拼接用户传入的 URL。
type InstrumentClient struct {
	client                 *Client
	code, symbol, currency string
}

func NewInstrumentClient(c *Client, code, symbol, currency string) *InstrumentClient {
	return &InstrumentClient{c, code, symbol, currency}
}
func (c *InstrumentClient) FetchGoldQuote(ctx context.Context) (domain.GoldQuote, error) {
	body, err := c.client.get(ctx, "https://hq.sinajs.cn/list="+c.code+",fx_susdcny")
	if err != nil {
		return domain.GoldQuote{}, err
	}
	return parseInstrumentQuote(body, c.code, c.symbol, c.currency)
}
func (c *InstrumentClient) FetchGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error) {
	if !strings.HasPrefix(c.code, "hf_") {
		return nil, fmt.Errorf("Sina daily unavailable for %s", c.symbol)
	}
	body, err := c.client.get(ctx, strings.Replace(dailyEndpoint, "symbol=XAU", "symbol="+strings.TrimPrefix(c.code, "hf_"), 1))
	if err != nil {
		return nil, err
	}
	return parseDailyBody(body)
}
func (c *InstrumentClient) FetchGoldIntraday(ctx context.Context) ([]domain.IntradayPoint, error) {
	if !strings.HasPrefix(c.code, "hf_") {
		return nil, fmt.Errorf("Sina intraday unavailable for %s", c.symbol)
	}
	body, err := c.client.get(ctx, strings.Replace(intradayEndpoint, "symbol=XAU", "symbol="+strings.TrimPrefix(c.code, "hf_"), 1))
	if err != nil {
		return nil, err
	}
	return parseIntradayBody(body)
}
func parseInstrumentQuote(body []byte, code, symbol, currency string) (domain.GoldQuote, error) {
	f, err := extractFields(string(body), code)
	if err != nil {
		return domain.GoldQuote{}, err
	}
	if len(f) < 13 {
		return domain.GoldQuote{}, fmt.Errorf("short %s quote", code)
	}
	value := func(i int) (float64, error) {
		p, e := strconv.ParseFloat(strings.TrimSpace(f[i]), 64)
		if e != nil || p <= 0 || math.IsNaN(p) || math.IsInf(p, 0) {
			return 0, fmt.Errorf("invalid %s field %d", code, i)
		}
		return p, nil
	}
	q := domain.GoldQuote{Symbol: symbol, Currency: currency, USDCNY: parseUSDCNY(string(body))}
	if q.Price, err = value(0); err != nil {
		return q, err
	}
	// 公共报价字段：2/3 为买卖价，7 昨收，8 今开。不能把买价当开盘价。
	if q.PrevClose, err = value(7); err != nil {
		return q, err
	}
	if q.Open, err = value(8); err != nil {
		return q, err
	}
	if q.High, err = value(4); err != nil {
		return q, err
	}
	if q.Low, err = value(5); err != nil {
		return q, err
	}
	q.AsOf, err = time.ParseInLocation("2006-01-02 15:04:05", f[12]+" "+f[6], beijingZone)
	return q, err
}
