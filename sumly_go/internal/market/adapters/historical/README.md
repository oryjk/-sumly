# Annual gold reference data

Source: USGS Data Series 140, Gold, 2022 update (public domain).
https://www.usgs.gov/media/files/gold-historical-statistics-data-series-140
Workbook: https://d9-wret.s3.us-west-2.amazonaws.com/assets/palladium/production/s3fs-public/media/files/ds140-gold-2022.xlsx
Retrieved 2026-09-29. SHA-256: 025f3eb98adb606cc214b82caa70646b80cf9debdf6544dbafce361283c1c480

Extracted Gold worksheet rows for 1900–2015 inclusive, column G `Unit value ($/t)` (nominal dollars, not column H inflation-adjusted dollars). The embedded worksheet notes describe this as estimated using average world market gold prices through 1967 and Engelhard average refined gold price quotations from 1968 onward. Original values and their published precision are preserved in CSV. Conversion to USD/troy oz multiplies by 31.1034768 / 1,000,000.

One annual point is placed at July 1 solely for chart positioning; it is not a quote for July 1. API marks it `annual` and attributes `usgs-ds140`. From 2016 the API uses existing Sina London gold daily closes marked `daily`. These are different price series/aggregation methods, explicitly disclosed in the UI. No daily OHLC data are invented from annual references. Weekends, holidays and missing source days are not filled. Current FX conversion in the app is a presentation conversion, not historical CNY prices.
