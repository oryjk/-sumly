package sina

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
)

const (
	quoteEndpoint = "https://hq.sinajs.cn/list=hf_XAU,fx_susdcny"
	dailyEndpoint = "https://stock.finance.sina.com.cn/futures/api/jsonp.php/var%20t=/GlobalFuturesService.getGlobalFuturesDailyKLine?symbol=XAU"
	referer       = "https://finance.sina.com.cn"
	maxBodyBytes  = 8 << 20 // 日线全量约 500KB，留足余量
	goldSymbol    = "XAUUSD"
)

// beijingZone 新浪行情的时间戳按北京时间给出；固定 +8 避免依赖 tzdata。
var beijingZone = time.FixedZone("CST", 8*3600)

// Client 从新浪财经抓取伦敦金行情（ hf_XAU 实时报价 + 全球期货日线）。
type Client struct {
	httpClient *http.Client
}

var _ ports.GoldSource = (*Client)(nil)

func NewClient(httpClient *http.Client) *Client {
	return &Client{httpClient: httpClient}
}

func (c *Client) FetchGoldQuote(ctx context.Context) (domain.GoldQuote, error) {
	body, err := c.get(ctx, quoteEndpoint)
	if err != nil {
		return domain.GoldQuote{}, fmt.Errorf("fetch gold quote: %w", err)
	}
	return parseQuoteBody(body)
}

func (c *Client) FetchGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error) {
	body, err := c.get(ctx, dailyEndpoint)
	if err != nil {
		return nil, fmt.Errorf("fetch gold daily klines: %w", err)
	}
	return parseDailyBody(body)
}

func (c *Client) get(ctx context.Context, endpoint string) ([]byte, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	// hq.sinajs.cn 自 2021 起强制校验 Referer
	request.Header.Set("Referer", referer)

	response, err := c.httpClient.Do(request)
	if err != nil {
		return nil, fmt.Errorf("call sina: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return nil, fmt.Errorf("sina returned HTTP %d", response.StatusCode)
	}
	return io.ReadAll(io.LimitReader(response.Body, maxBodyBytes))
}

// parseQuoteBody 解析 `var hq_str_hf_XAU="…";\nvar hq_str_fx_susdcny="…";` 形式的组合实时报价。
// 开盘、昨收与买卖价通过共用适配器解析，避免不同入口口径不一致。
func parseQuoteBody(body []byte) (domain.GoldQuote, error) {
	return parseInstrumentQuote(body, "hf_XAU", "XAUUSD", "USD")
}

// extractFields 取 `var hq_str_<symbol>="f1,f2,…";` 中引号内的逗号字段。
func extractFields(text, symbol string) ([]string, error) {
	marker := "hq_str_" + symbol + "=\""
	start := strings.Index(text, marker)
	if start < 0 {
		return nil, fmt.Errorf("sina payload missing %s quote", symbol)
	}
	start += len(marker)
	end := strings.Index(text[start:], `"`)
	if end < 0 {
		return nil, fmt.Errorf("sina %s quote is unterminated", symbol)
	}
	return strings.Split(text[start:start+end], ","), nil
}

// parseUSDCNY 解析在岸人民币汇率，取买/卖中间价，逐级回退到最新价字段。
// 布局：0 时间、1 买价、2 卖价、…、5 最新价、…；解析失败返回 0。
func parseUSDCNY(text string) float64 {
	fields, err := extractFields(text, "fx_susdcny")
	if err != nil || len(fields) < 6 {
		return 0
	}
	bid := parseOptionalFloat(fields[1])
	ask := parseOptionalFloat(fields[2])
	if bid > 0 && ask > 0 {
		return (bid + ask) / 2
	}
	return parseOptionalFloat(fields[5])
}

func parseOptionalFloat(raw string) float64 {
	value, err := strconv.ParseFloat(strings.TrimSpace(raw), 64)
	if err != nil {
		return 0
	}
	return value
}

type dailyRow struct {
	Date  string `json:"date"`
	Open  string `json:"open"`
	High  string `json:"high"`
	Low   string `json:"low"`
	Close string `json:"close"`
}

// parseDailyBody 解析 `var t=([{…}]);` 形式的日线 JSONP：取首个 `[` 到最后一个 `]` 的 JSON 数组。
func parseDailyBody(body []byte) ([]domain.DailyBar, error) {
	text := string(body)
	start := strings.Index(text, "[")
	end := strings.LastIndex(text, "]")
	if start < 0 || end <= start {
		return nil, errors.New("sina daily payload has no JSON array")
	}
	var rows []dailyRow
	if err := json.Unmarshal([]byte(text[start:end+1]), &rows); err != nil {
		return nil, fmt.Errorf("decode sina daily rows: %w", err)
	}

	bars := make([]domain.DailyBar, 0, len(rows))
	for _, row := range rows {
		date, err := time.ParseInLocation("2006-01-02", strings.TrimSpace(row.Date), beijingZone)
		if err != nil {
			continue // 坏行跳过，不阻断整份序列
		}
		bar := domain.DailyBar{Date: date}
		var parseErr error
		if bar.Open, parseErr = strconv.ParseFloat(strings.TrimSpace(row.Open), 64); parseErr != nil {
			continue
		}
		if bar.High, parseErr = strconv.ParseFloat(strings.TrimSpace(row.High), 64); parseErr != nil {
			continue
		}
		if bar.Low, parseErr = strconv.ParseFloat(strings.TrimSpace(row.Low), 64); parseErr != nil {
			continue
		}
		if bar.Close, parseErr = strconv.ParseFloat(strings.TrimSpace(row.Close), 64); parseErr != nil {
			continue
		}
		bars = append(bars, bar)
	}
	if len(bars) == 0 {
		return nil, errors.New("sina daily payload has no valid rows")
	}
	// 新浪按时间升序返回，这里做一次防御性排序
	sort.Slice(bars, func(i, j int) bool { return bars[i].Date.Before(bars[j].Date) })
	return bars, nil
}
