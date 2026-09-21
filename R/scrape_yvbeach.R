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

# Records a step output when running inside GitHub Actions; no-op locally.
set_gh_output <- function(name, value) {
  gh_output <- Sys.getenv("GITHUB_OUTPUT")
  if (nzchar(gh_output)) {
    cat(paste0(name, "=", value, "\n"), file = gh_output, append = TRUE)
  }
}

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

pression_mb <- extract_num("PRESSION\\s*:\\s*(-?[\\d.]+)\\s*mb")
rafale_kmh  <- extract_num("RAFALE\\s*max/1h\\s*:\\s*(-?[\\d.]+)\\s*km/h")
vent_kmh    <- extract_num("VENT\\s*moy/10min\\s*:\\s*(-?[\\d.]+)\\s*km/h")

dir_match <- str_match(
  text,
  "DIRECTION\\s*moy/10min\\s*:\\s*([A-Z]+)\\s*-\\s*(-?[\\d.]+)\\s*°"
)
direction_cardinale <- dir_match[, 2]
direction_deg <- as.numeric(dir_match[, 3])

temperature_c     <- extract_num("TEMPERATURE\\s*:\\s*(-?[\\d.]+)\\s*°C")
temperature_lac_c <- extract_num("TEMP DU LAC\\s*:\\s*(-?[\\d.]+)\\s*°C")
humidite_pct      <- extract_num("HUMIDITE\\s*:\\s*(-?[\\d.]+)\\s*%")
point_de_rosee_c  <- extract_num("POINT DE ROSEE\\s*:\\s*(-?[\\d.]+)\\s*°C")
pluie_du_jour_mm  <- extract_num("PLUIE DU JOUR\\s*:\\s*(-?[\\d.]+)\\s*mm")

new_row <- tibble(
  timestamp           = measured_at,
  pression_mb         = pression_mb,
  rafale_kt           = kmh_to_knots(rafale_kmh),
  vent_kt             = kmh_to_knots(vent_kmh),
  direction_cardinale = direction_cardinale,
  direction_deg       = direction_deg,
  temperature_c       = temperature_c,
  temperature_lac_c   = temperature_lac_c,
  humidite_pct        = humidite_pct,
  point_de_rosee_c    = point_de_rosee_c,
  pluie_du_jour_mm    = pluie_du_jour_mm
)

required <- setdiff(names(new_row), character(0))
if (anyNA(new_row[required])) {
  print(new_row)
  stop("One or more fields failed to parse - aborting to avoid writing a bad row")
}

if (file.exists(csv_path)) {
  existing <- read_csv(csv_path, col_types = cols(
    timestamp           = col_datetime(),
    pression_mb         = col_double(),
    rafale_kt           = col_double(),
    vent_kt             = col_double(),
    direction_cardinale = col_character(),
    direction_deg       = col_double(),
    temperature_c       = col_double(),
    temperature_lac_c   = col_double(),
    humidite_pct        = col_double(),
    point_de_rosee_c    = col_double(),
    pluie_du_jour_mm    = col_double()
  ))
  if (nrow(existing) > 0 && max(existing$timestamp) >= new_row$timestamp) {
    message("No new measurement since last scrape - skipping")
    set_gh_output("new_data", "false")
    quit(save = "no", status = 0)
  }
  out <- bind_rows(existing, new_row)
} else {
  dir.create(dirname(csv_path), showWarnings = FALSE, recursive = TRUE)
  out <- new_row
}

write_csv(out, csv_path)
message("Wrote row for ", format(new_row$timestamp, "%Y-%m-%d %H:%M %Z"))
set_gh_output("new_data", "true")
