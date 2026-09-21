#!/usr/bin/env Rscript
#
# Scrapes the live weather widget on kitesailing.ch's Silvaplana spot page
# (Lake Silvaplana, Engadin, Switzerland) and appends one row to
# data/silvaplana.csv, keyed on the measurement timestamp reported by the
# widget itself (not the scrape time). Same LiveMeteo-widget-backed pattern
# as R/scrape_yvbeach.R, just different field labels (German) and a
# narrower set of fields (no lake temperature/dew point/rain here).

library(httr2)
library(rvest)
library(stringr)
library(lubridate)
library(readr)
library(dplyr)

url <- "https://www.kitesailing.ch/en/spot/weather-watersports"
csv_path <- "data/silvaplana.csv"

kmh_to_knots <- function(x) x * 0.539957

# German compass abbreviations (as used by the widget) to English.
direction_map <- c(
  N = "N", NO = "NE", O = "E", SO = "SE",
  S = "S", SW = "SW", W = "W", NW = "NW"
)

page <- request(url) |>
  req_perform() |>
  resp_body_html()

widget <- page |> html_element(".container--liveweather")
if (is.na(widget)) {
  stop("Could not find the live weather widget on the page - site layout may have changed")
}

text <- widget |>
  html_text2() |>
  str_squish()

time_match <- str_match(
  text,
  "[A-Za-z]+,\\s*(\\d{1,2})\\.(\\d{1,2})\\.(\\d{4})\\s*\\((\\d{1,2}):(\\d{2}):(\\d{2})\\)"
)
if (anyNA(time_match)) {
  stop("Could not parse measurement timestamp from page")
}

measured_at <- make_datetime(
  year  = as.integer(time_match[, 4]),
  month = as.integer(time_match[, 3]),
  day   = as.integer(time_match[, 2]),
  hour  = as.integer(time_match[, 5]),
  min   = as.integer(time_match[, 6]),
  sec   = as.integer(time_match[, 7]),
  tz    = "Europe/Zurich"
)

temperature_c <- as.numeric(str_match(text, "(-?[\\d.]+)\\s*°C")[, 2])

gust_match <- str_match(text, "Windspitzen\\s*(-?[\\d.]+)\\s*km/h\\s*\\((-?[\\d.]+)\\s*kn\\)")
gust_kt <- as.numeric(gust_match[, 3])

humidity_pct <- as.numeric(str_match(text, "Feuchtigkeit:\\s*(-?[\\d.]+)\\s*%")[, 2])
pressure_mb  <- as.numeric(str_match(text, "Luftdruck:\\s*(-?[\\d.]+)\\s*hPa")[, 2])

dir_match <- str_match(text, "Windrichtung:\\s*([A-Z]+)\\s*\\((-?[\\d.]+)\\s*°\\)")
wind_direction_cardinal_raw <- dir_match[, 2]
wind_direction_deg <- as.numeric(dir_match[, 3])

wind_match <- str_match(text, "Mittelwind:\\s*(-?[\\d.]+)\\s*km/h\\s*\\((\\d+)\\s*Bft\\)")
wind_kmh <- as.numeric(wind_match[, 2])

if (!wind_direction_cardinal_raw %in% names(direction_map)) {
  stop("Unrecognised wind direction abbreviation: ", wind_direction_cardinal_raw)
}
wind_direction_cardinal <- unname(direction_map[wind_direction_cardinal_raw])

new_row <- tibble(
  timestamp               = measured_at,
  pressure_mb             = pressure_mb,
  gust_kt                 = gust_kt,
  wind_kt                 = kmh_to_knots(wind_kmh),
  wind_direction_cardinal = wind_direction_cardinal,
  wind_direction_deg      = wind_direction_deg,
  temperature_c           = temperature_c,
  humidity_pct            = humidity_pct
)

if (anyNA(new_row)) {
  print(new_row)
  stop("One or more fields failed to parse - aborting to avoid writing a bad row")
}

if (file.exists(csv_path)) {
  existing <- read_csv(csv_path, col_types = cols(
    timestamp               = col_datetime(),
    pressure_mb             = col_double(),
    gust_kt                 = col_double(),
    wind_kt                 = col_double(),
    wind_direction_cardinal = col_character(),
    wind_direction_deg      = col_double(),
    temperature_c           = col_double(),
    humidity_pct            = col_double()
  ))
  if (nrow(existing) > 0 && max(existing$timestamp) >= new_row$timestamp) {
    message("No new measurement since last scrape - skipping")
    quit(save = "no", status = 0)
  }
  out <- bind_rows(existing, new_row)
} else {
  dir.create(dirname(csv_path), showWarnings = FALSE, recursive = TRUE)
  out <- new_row
}

write_csv(out, csv_path)
message("Wrote row for ", format(new_row$timestamp, "%Y-%m-%d %H:%M %Z"))
