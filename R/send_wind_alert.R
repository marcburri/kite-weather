#!/usr/bin/env Rscript
#
# Sends an email when average wind speed crosses WIND_THRESHOLD_KT from
# below to at-or-above it (a rising edge), so a sustained windy spell only
# triggers one email instead of one per hourly run. Intended to run right
# after R/scrape_yvbeach.R, only when that script appended a new row.
#
# Required environment variables:
#   GMAIL_USERNAME     - sending Gmail address
#   GMAIL_APP_PASSWORD - Gmail app password for that address
#   ALERT_EMAIL_TO     - recipient address

library(readr)
library(dplyr)
library(glue)
library(blastula)

csv_path <- "data/yvbeach.csv"
wind_threshold_kt <- 15

df <- read_csv(csv_path, show_col_types = FALSE)
if (nrow(df) < 1) {
  message("No data yet - nothing to check")
  quit(save = "no", status = 0)
}

latest <- df[nrow(df), ]
previous_kt <- if (nrow(df) >= 2) df$vent_kt[nrow(df) - 1] else -Inf

is_rising_edge <- latest$vent_kt >= wind_threshold_kt && previous_kt < wind_threshold_kt

if (!is_rising_edge) {
  message(
    "No alert-worthy transition (latest vent = ", round(latest$vent_kt, 1),
    " kt, previous = ", round(previous_kt, 1), " kt)"
  )
  quit(save = "no", status = 0)
}

from_email <- Sys.getenv("GMAIL_USERNAME")
to_email   <- Sys.getenv("ALERT_EMAIL_TO")

if (!nzchar(from_email) || !nzchar(to_email)) {
  stop("GMAIL_USERNAME and ALERT_EMAIL_TO must be set")
}

body_text <- glue(
  "Wind just picked up at YvBeach (Yvonand, Lake Neuchatel):\n\n",
  "- Vent (10-min avg): {round(latest$vent_kt, 1)} kt\n",
  "- Rafale (gust, max/1h): {round(latest$rafale_kt, 1)} kt\n",
  "- Direction: {latest$direction_cardinale} ({latest$direction_deg} deg)\n",
  "- Air temperature: {latest$temperature_c} C\n",
  "- Lake temperature: {latest$temperature_lac_c} C\n",
  "- Measured at: {format(latest$timestamp, '%Y-%m-%d %H:%M UTC')}\n\n",
  "Live station: https://yvbeach.com/yvmeteo.htm"
)

email <- compose_email(body = md(body_text))

smtp_send(
  email,
  to = to_email,
  from = from_email,
  subject = glue("Wind alert: {round(latest$vent_kt, 1)} kt at YvBeach"),
  credentials = creds_envvar(
    user = from_email,
    pass_envvar = "GMAIL_APP_PASSWORD",
    provider = "gmail"
  )
)

message("Sent wind alert email (", round(latest$vent_kt, 1), " kt)")
