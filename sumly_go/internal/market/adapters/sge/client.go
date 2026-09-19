package sge

import (
	"context"
	"encoding/json"
	"fmt"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"io"
	"math"
	"net/http"
	"sort"
	"strings"
	"time"
)

type Client struct{ HTTP *http.Client }

func (c *Client) FetchGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://www.sge.com.cn/graph/Dailyhq", strings.NewReader("instid=Au99.99"))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("User-Agent", "Mozilla/5.0")
	req.Header.Set("Referer", "https://www.sge.com.cn/")
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("SGE daily HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, err
	}
	return parseDaily(body)
}
func parseDaily(body []byte) ([]domain.DailyBar, error) {
	var response struct {
		Rows [][]json.RawMessage `json:"time"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, err
	}
	bars := make([]domain.DailyBar, 0, len(response.Rows))
	seen := map[string]bool{}
	for _, row := range response.Rows {
		if len(row) != 5 {
			continue
		}
		var date string
		if json.Unmarshal(row[0], &date) != nil || seen[date] {
			continue
		}
		day, err := time.ParseInLocation("2006-01-02", date, time.FixedZone("CST", 8*3600))
		if err != nil {
			continue
		}
		values := make([]float64, 4)
		valid := true
		for i := range values {
			if json.Unmarshal(row[i+1], &values[i]) != nil || values[i] <= 0 || math.IsNaN(values[i]) || math.IsInf(values[i], 0) {
				valid = false
			}
		}
		if !valid || values[2] > values[3] || values[0] < values[2] || values[0] > values[3] || values[1] < values[2] || values[1] > values[3] {
			continue
		}
		bars = append(bars, domain.DailyBar{Date: day, Open: values[0], Close: values[1], Low: values[2], High: values[3]})
		seen[date] = true
	}
	if len(bars) == 0 {
		return nil, fmt.Errorf("SGE daily contains no valid bars")
	}
	sort.Slice(bars, func(i, j int) bool { return bars[i].Date.Before(bars[j].Date) })
	return bars, nil
}
