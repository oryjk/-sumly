package sina

import (
	"testing"
	"time"
)

func TestParseIntraday(t *testing.T) {
	body := []byte(`var t=({"minLine_1d":[["2026-09-18","4300","LIFFE","","06:00","4343.970","0","0","4343.568","2026-09-18 06:00:00"],["06:01","4342.770","0","0","4343.600","2026-09-18 06:01:00"],["06:02","NaN","0","0","0","2026-09-18 06:02:00"]]});`)
	points, err := parseIntradayBody(body)
	if err != nil {
		t.Fatal(err)
	}
	if len(points) != 2 || points[0].Price != 4343.970 || points[1].Price != 4342.770 {
		t.Fatalf("unexpected points: %+v", points)
	}
	if points[0].Time.Format(time.RFC3339) != "2026-09-18T06:00:00+08:00" {
		t.Fatal(points[0].Time)
	}
}

func TestParseIntradayRejectsEmpty(t *testing.T) {
	for _, body := range []string{`var t=({"minLine_1d":[]});`, `garbage`, `var t=({"__ERROR":3});`} {
		if _, err := parseIntradayBody([]byte(body)); err == nil {
			t.Fatalf("expected error for %s", body)
		}
	}
}
