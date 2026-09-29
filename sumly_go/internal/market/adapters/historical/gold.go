package historical

import (
	_ "embed"
	"encoding/csv"
	"fmt"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"strconv"
	"strings"
	"time"
)

//go:embed gold_annual_1900_2015.csv
var annualCSV string

func AnnualGold() ([]domain.GoldHistoryPoint, error) {
	rows, err := csv.NewReader(strings.NewReader(annualCSV)).ReadAll()
	if err != nil {
		return nil, err
	}
	if len(rows) != 117 {
		return nil, fmt.Errorf("annual gold coverage must be 1900–2015")
	}
	points := make([]domain.GoldHistoryPoint, 0, 116)
	for i, row := range rows[1:] {
		if len(row) != 2 {
			return nil, fmt.Errorf("invalid annual gold row")
		}
		year, err := strconv.Atoi(row[0])
		if err != nil || year != 1900+i {
			return nil, fmt.Errorf("annual gold year gap")
		}
		value, err := strconv.ParseFloat(row[1], 64)
		if err != nil || value <= 0 {
			return nil, fmt.Errorf("invalid annual gold value")
		}
		points = append(points, domain.GoldHistoryPoint{Date: time.Date(year, 7, 1, 12, 0, 0, 0, time.UTC), Price: value * domain.GramsPerTroyOunce / 1000000, Granularity: "annual", Source: "usgs-ds140"})
	}
	return points, nil
}
