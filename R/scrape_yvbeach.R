#!/usr/bin/env Rscript
#
# Scrapes the live conditions page of the YvBeach weather station
# (Yvonand, Lake Neuchatel, Switzerland) and appends one row to
# data/yvbeach.csv, keyed on the measurement timestamp reported by the
# station itself (not the scrape time).

library(httr2)
library(rvest)
library(stringr)
library(lubridate)
library(readr)
library(dplyr)

url <- "https://yvbeach.com/yvmeteo.htm"
csv_path <- "data/yvbeach.csv"

kmh_to_knots <- function(x) x * 0.539957

page <- request(url) |>
  req_perform() |>
  resp_body_html()

text <- page |>
  html_text2() |>
  str_squish()

extract_num <- function(pattern) {
  m <- str_match(text, pattern)
  as.numeric(m[, 2])
}

date_match <- str_match(
  text,
  "RELEVE DU\\s+(\\d{1,2})/(\\d{1,2})/(\\d{4})\\s+A\\s+(\\d{1,2})h(\\d{2})"
)
if (anyNA(date_match)) {
  stop("Could not parse measurement timestamp from page")
}

measured_at <- make_datetime(
  year  = as.integer(date_match[, 4]),
  month = as.integer(date_match[, 3]),
  day   = as.integer(date_match[, 2]),
  hour  = as.integer(date_match[, 5]),
  min   = as.integer(date_match[, 6]),
  tz    = "Europe/Zurich"
)

pressure_mb  <- extract_num("PRESSION\\s*:\\s*(-?[\\d.]+)\\s*mb")
gust_kmh     <- extract_num("RAFALE\\s*max/1h\\s*:\\s*(-?[\\d.]+)\\s*km/h")
wind_kmh     <- extract_num("VENT\\s*moy/10min\\s*:\\s*(-?[\\d.]+)\\s*km/h")

dir_match <- str_match(
  text,
  "DIRECTION\\s*moy/10min\\s*:\\s*([A-Z]+)\\s*-\\s*(-?[\\d.]+)\\s*°"
)
wind_direction_cardinal <- dir_match[, 2]
wind_direction_deg <- as.numeric(dir_match[, 3])

temperature_c      <- extract_num("TEMPERATURE\\s*:\\s*(-?[\\d.]+)\\s*°C")
lake_temperature_c <- extract_num("TEMP DU LAC\\s*:\\s*(-?[\\d.]+)\\s*°C")
humidity_pct       <- extract_num("HUMIDITE\\s*:\\s*(-?[\\d.]+)\\s*%")
dew_point_c        <- extract_num("POINT DE ROSEE\\s*:\\s*(-?[\\d.]+)\\s*°C")
rain_today_mm      <- extract_num("PLUIE DU JOUR\\s*:\\s*(-?[\\d.]+)\\s*mm")

new_row <- tibble(
  timestamp               = measured_at,
  pressure_mb             = pressure_mb,
  gust_kt                 = kmh_to_knots(gust_kmh),
  wind_kt                 = kmh_to_knots(wind_kmh),
  wind_direction_cardinal = wind_direction_cardinal,
  wind_direction_deg      = wind_direction_deg,
  temperature_c           = temperature_c,
  lake_temperature_c      = lake_temperature_c,
  humidity_pct            = humidity_pct,
  dew_point_c             = dew_point_c,
  rain_today_mm           = rain_today_mm
)

required <- setdiff(names(new_row), character(0))
if (anyNA(new_row[required])) {
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
    lake_temperature_c      = col_double(),
    humidity_pct            = col_double(),
    dew_point_c             = col_double(),
    rain_today_mm           = col_double()
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
