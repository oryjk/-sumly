package application

import (
	"context"
	"errors"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

func (s *GoldMarketService) GetGoldIntraday(ctx context.Context) ([]domain.IntradayPoint, error) {
	s.intradayMu.Lock()
	defer s.intradayMu.Unlock()
	if len(s.intraday) > 0 && s.now().Sub(s.intradayAt) < 15*time.Second {
		return append([]domain.IntradayPoint(nil), s.intraday...), nil
	}
	source, ok := s.source.(ports.GoldIntradaySource)
	if !ok {
		return nil, sharederror.Wrap(sharederror.KindInternal, "行情源不支持分时", errors.New("intraday unsupported"))
	}
	points, err := source.FetchGoldIntraday(ctx)
	if err != nil {
		if len(s.intraday) > 0 {
			return append([]domain.IntradayPoint(nil), s.intraday...), nil
		}
		return nil, sharederror.Wrap(sharederror.KindInternal, "分时行情暂时不可用", err)
	}
	s.intraday, s.intradayAt = append([]domain.IntradayPoint(nil), points...), s.now()
	return points, nil
}
