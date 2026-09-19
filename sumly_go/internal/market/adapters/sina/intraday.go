package sina

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

const intradayEndpoint = "https://stock.finance.sina.com.cn/futures/api/jsonp.php/var%20t=/GlobalFuturesService.getGlobalFuturesMinLine?symbol=XAU"

func (c *Client) FetchGoldIntraday(ctx context.Context) ([]domain.IntradayPoint, error) {
	body, err := c.get(ctx, intradayEndpoint)
	if err != nil {
		return nil, err
	}
	return parseIntradayBody(body)
}

func parseIntradayBody(body []byte) ([]domain.IntradayPoint, error) {
	text := string(body)
	start, end := strings.Index(text, "{"), strings.LastIndex(text, "}")
	if start < 0 || end <= start {
		return nil, errors.New("invalid intraday JSONP")
	}
	var payload struct {
		Rows [][]string `json:"minLine_1d"`
	}
	if err := json.Unmarshal([]byte(text[start:end+1]), &payload); err != nil {
		return nil, err
	}
	points := make([]domain.IntradayPoint, 0, len(payload.Rows))
	seen := make(map[time.Time]bool)
	for _, row := range payload.Rows {
		// 首行有交易日、昨收等四个额外字段；每行最后六项结构一致。
		if len(row) < 6 {
			continue
		}
		row = row[len(row)-6:]
		date, err := time.ParseInLocation("2006-01-02 15:04:05", row[5], beijingZone)
		if err != nil {
			continue
		}
		price, err := strconv.ParseFloat(row[1], 64)
		if err != nil || price <= 0 || math.IsNaN(price) || math.IsInf(price, 0) || seen[date] {
			continue
		}
		seen[date] = true
		points = append(points, domain.IntradayPoint{Time: date, Price: price})
	}
	if len(points) == 0 {
		return nil, errors.New("no valid intraday points")
	}
	sort.Slice(points, func(i, j int) bool { return points[i].Time.Before(points[j].Time) })
	return points, nil
}
