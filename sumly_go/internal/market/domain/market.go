package domain

import "time"

// GramsPerTroyOunce 金衡盎司换算：1 盎司 = 31.1034768 克。
const GramsPerTroyOunce = 31.1034768

// GoldQuote 原始报价；Currency 为 CNY 时单位元/克，否则美元/金衡盎司。
type GoldQuote struct {
	SourceDelaySeconds int
	Currency           string
	Symbol             string
	Price              float64
	Open               float64
	High               float64
	Low                float64
	PrevClose          float64
	USDCNY             float64 // 美元兑人民币汇率；0 表示不可用
	AsOf               time.Time
}

// CNYPerGram 每克人民币价；汇率缺失时返回 0。
func (q GoldQuote) CNYPerGram() float64 {
	if q.Currency == "CNY" {
		return q.Price
	}
	if q.USDCNY == 0 {
		return 0
	}
	return q.Price / GramsPerTroyOunce * q.USDCNY
}

// Change 当日涨跌 = 最新价 − 昨收。
func (q GoldQuote) Change() float64 {
	return q.Price - q.PrevClose
}

// ChangePercent 当日涨跌幅（百分数）；昨收缺失时返回 0。
func (q GoldQuote) ChangePercent() float64 {
	if q.PrevClose == 0 {
		return 0
	}
	return q.Change() / q.PrevClose * 100
}

// DailyBar 单个交易日 OHLC，使用该品种的原始报价单位。
type DailyBar struct {
	Date  time.Time
	Open  float64
	High  float64
	Low   float64
	Close float64
}

// IntradayPoint 分钟报价，价格单位美元/盎司，时间为北京时间。
type IntradayPoint struct {
	Time  time.Time
	Price float64
}

// RealtimePoint 真实采样；原始品种接口使用品种单位，旧接口使用人民币/克。
// Time 为采样时间（延迟源使用事件时间），SourceTime 为上游事件时间。
type RealtimePoint struct {
	SourceTime time.Time
	Time       time.Time
	Price      float64
}
