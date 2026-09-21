# kite-weather

Hourly scrapes of weather stations useful for kiting/wakeboarding/wind
sports, into growing CSVs, run via scheduled GitHub Actions.

Currently scraped:

- [YvBeach weather station](https://yvbeach.com/yvmeteo.htm) (Yvonand, Lake
  Neuchatel, Switzerland) → [`data/yvbeach.csv`](data/yvbeach.csv)
- [Kitesailing.ch live weather](https://www.kitesailing.ch/en/spot/weather-watersports)
  (Lake Silvaplana, Engadin, Switzerland) → [`data/silvaplana.csv`](data/silvaplana.csv)

Neither site has an API — both are plain server-rendered HTML pages that
embed a live station reading as text. This scrapes those text fields
directly.

## Data

### YvBeach

`data/yvbeach.csv`, one row appended per run (rows are skipped if the
station's own measurement timestamp hasn't advanced since the last scrape,
so there are no duplicate/stale rows even if a run happens to catch a stale
page).

| column                     | meaning                                    | unit               |
|-----------------------------|---------------------------------------------|--------------------|
| `timestamp`                 | time of the *measurement*, per the station   | UTC (ISO 8601)     |
| `pressure_mb`                | atmospheric pressure                         | millibar           |
| `gust_kt`                    | wind gust, max over last hour                | knots (converted from km/h) |
| `wind_kt`                    | wind speed, 10-minute average                | knots (converted from km/h) |
| `wind_direction_cardinal`    | wind direction, 10-minute average            | compass point (e.g. `NE`) |
| `wind_direction_deg`         | wind direction, 10-minute average            | degrees            |
| `temperature_c`              | air temperature                              | °C                 |
| `lake_temperature_c`         | lake water temperature                       | °C                 |
| `humidity_pct`               | relative humidity                            | %                  |
| `dew_point_c`                | dew point                                    | °C                 |
| `rain_today_mm`              | rainfall accumulated so far today            | mm                 |

**Dew point** (`dew_point_c`) is the temperature air would need to cool to,
at the current pressure and moisture content, for water vapor to condense
into dew/fog. It tracks absolute moisture content better than relative
humidity: the closer it is to the air temperature, the muggier it feels,
and if the air temperature drops to the dew point, condensation forms.

Wind speed and gust are converted from the source site's km/h to knots
(`1 km/h = 0.539957 kt`); everything else is reported as-is.

### Silvaplana

`data/silvaplana.csv`, same one-row-per-run / skip-if-stale behaviour as
YvBeach above. The site's live widget exposes fewer fields than YvBeach's
(no lake temperature, dew point, or rainfall), so this CSV has fewer
columns rather than padding them out with fabricated data.

| column                     | meaning                                    | unit               |
|-----------------------------|---------------------------------------------|--------------------|
| `timestamp`                 | time of the *measurement*, per the widget    | UTC (ISO 8601)     |
| `pressure_mb`                | atmospheric pressure                         | millibar (= hPa)   |
| `gust_kt`                    | wind gust                                    | knots (as reported by the site) |
| `wind_kt`                    | mean wind speed                              | knots (converted from km/h) |
| `wind_direction_cardinal`    | wind direction                               | compass point (translated from the site's German abbreviation, e.g. `NO` → `NE`) |
| `wind_direction_deg`         | wind direction                               | degrees            |
| `temperature_c`              | air temperature                              | °C                 |
| `humidity_pct`               | relative humidity                            | %                  |

`gust_kt` uses the knot value the site reports directly (computed there
from unrounded sensor data), rather than re-deriving it from the rounded
km/h figure shown alongside it — that avoids a small but avoidable
rounding error. `wind_kt` has no such site-provided value, so it's
converted from km/h the same way as YvBeach's columns.

## Running it yourself

```r
# needs: httr2, rvest, stringr, lubridate, readr, dplyr
Rscript R/scrape_yvbeach.R
Rscript R/scrape_silvaplana.R
```

## Schedule

Runs hourly via [`.github/workflows/scrape.yml`](.github/workflows/scrape.yml)
(`cron: '0 * * * *'`), and can also be triggered manually from the Actions
tab (`workflow_dispatch`).
