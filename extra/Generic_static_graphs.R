library(covidregionaldata)
library(ggplot2)
library(ggridges)
library(roll)
library(scales)
library(forcats)
# library(patchwork)
library(dplyr)
library(tidyr)

# Load data ----

if (!exists("country")) {
  country <- "France"
}

dataset_details <- get_available_datasets("regional") %>% filter(grepl(country, origin))

level_1_data <- get_regional_data(
  country = country,
  totals = FALSE,
  level = 1,
  localise = FALSE
)

if (!is.na(dataset_details$level_2_region)) {
  level_2_data <- get_regional_data(
    country = country,
    totals = FALSE,
    level = 2,
    localise = FALSE
  )
}

national_data <- level_1_data %>%
  group_by(date) %>%
  summarise(across(where(is.double), sum))

last_date <- format(max(level_1_data$date), "%B %d, %Y")

caption_text <- paste0(
  "Richard Martin-Nielsen | Data sourced through covidregionaldata, ",
  last_date
)

# Make summary table ----

if (!is.na(dataset_details$level_2_region)) {
  region_summaries <-
    level_2_data %>%
    group_by(level_2_region) %>%
    summarise(
      min_i = min(cases_new, na.rm = TRUE),
      max_i = max(cases_new, na.rm = TRUE),
      median_i = median(cases_new, na.rm = TRUE),
      mean_i = mean(cases_new, na.rm = TRUE)
    ) %>%
    rename(region = level_2_region)

  narrowed_regions <- pull(region_summaries %>% slice_max(max_i, n = 10) %>% select(region))

  narrowed_regional_incidence <- level_2_data %>%
    # filter(date < as_date("2021-01-04")) %>%
    filter(level_2_region %in% narrowed_regions)
}

# Set graphing defaults ----

theme_set(
  theme_minimal() +
    theme(plot.caption = element_text(size = 8))
)

# Plot ridgeline incidence for top 10 municipalities ----

if (!is.na(dataset_details$level_2_region)) {
  intercity_gap <- max(level_2_data$cases_new, na.rm = TRUE) / 2
  intercity_gap <- round(intercity_gap, -floor(log10(intercity_gap)))

  ridgeline_labels <- narrowed_regional_incidence %>%
    mutate(y = -as.numeric(factor(level_2_region)) * intercity_gap, region = level_2_region) %>%
    select(region, y) %>%
    unique()

  narrowed_regional_incidence %>%
    ggplot(aes(
      x = date, y = -as.numeric(factor(level_2_region)) * intercity_gap,
      height = cases_new, group = level_2_region
    )) + # y=as.numeric(level_2_region)*250
    geom_ridgeline(alpha = 0.5, aes(fill = level_2_region), size = 0.25) +
    scale_y_continuous(
      breaks = ridgeline_labels$y,
      labels = ridgeline_labels$region,
      sec.axis =
        sec_axis(~ . + 10,
          name = "Daily incidence (confirmed cases)",
          labels = rep(c(intercity_gap / 2, "0"), 10),
          breaks = seq(
            from = -intercity_gap / 2,
            to = -intercity_gap * 10,
            by = -intercity_gap / 2
          )
        ),
      name = "Region"
    ) +
    scale_x_date(date_breaks = "3 months", date_minor_breaks = "1 month", date_labels = "%B") +
    theme_ridges() +
    theme(plot.caption = element_text(size = 8)) +
    theme(legend.position = "none") +
    labs(
      x = "Date", y = "Region / Incidence",
      title = paste0("Regional COVID-19 incidence in ", country),
      subtitle = "Top ten level 2 regions by maximum daily incidence",
      caption = caption_text
    ) +
    theme(
      axis.text.y = element_text(size = 8),
      axis.title.y.left = element_blank()
    )

  ggsave(paste0("extra/", country, "-ridgeline-top-level-2-regions.png"), width = 6, height = 4, units = "in")
}

# Plot ridgeline incidence for all level 1 regions ----

intercity_gap <- max(level_1_data$cases_new, na.rm = TRUE) / 2
intercity_gap <- round(intercity_gap, -floor(log10(intercity_gap)))

ridgeline_labels <- level_1_data %>%
  filter(level_1_region != "Unknown") %>%
  mutate(y = -as.numeric(factor(level_1_region)) * intercity_gap, region = level_1_region) %>%
  select(region, y) %>%
  unique()

level_1_data %>%
  filter(level_1_region != "Unknown") %>%
  ggplot(aes(
    x = date, y = -as.numeric(factor(level_1_region)) * intercity_gap,
    height = cases_new, group = level_1_region
  )) + # y=as.numeric(level_2_region)*250
  geom_ridgeline(alpha = 0.5, aes(fill = level_1_region), size = 0.25) +
  scale_y_continuous(
    breaks = ridgeline_labels$y,
    labels = ridgeline_labels$region,
    sec.axis =
      sec_axis(~ . + 10,
        name = "Daily incidence (confirmed cases)",
        labels = rep(c(intercity_gap / 2, "0"), nrow(ridgeline_labels)),
        breaks = seq(
          from = -intercity_gap / 2,
          to = -intercity_gap * nrow(ridgeline_labels),
          by = -intercity_gap / 2
        )
      ),
    name = "Region"
  ) +
  scale_x_date(date_breaks = "3 months", date_minor_breaks = "1 month", date_labels = "%B") +
  theme_ridges() +
  theme(plot.caption = element_text(size = 8)) +
  theme(legend.position = "none") +
  labs(
    x = "Date", y = "Region / Incidence",
    title = paste0("Regional COVID-19 incidence in ", country),
    subtitle = "All level 1 regions",
    caption = caption_text
  ) +
  theme(
    axis.text.y = element_text(size = 8),
    axis.title.y.left = element_blank()
  )
ggsave(paste0("extra/", country, "-ridgeline-all-level-1-regions.png"), width = 6, height = 4, units = "in")

# Waterfall chart case counts - level 1 ----

# Attempt to calculate a "natural" bucket scale for the waterfalls
bucket_scale <- median(level_1_data$cases_new, na.rm = TRUE) * 2
if (bucket_scale < 20) {
  bucket_scale <- 20
}
bucket_scale <- floor(round(bucket_scale, -ceiling(log10(bucket_scale)) + 1)/20)*20
bucket_breaks <- c(-1, seq(from = 0, to = bucket_scale, length.out = 5), Inf)
bucket_labels <- c(
  0,
  paste(bucket_breaks[c(-1, -6, -7)],
    bucket_breaks[c(-1, -2, -7)],
    sep = "-"
  ),
  paste0(bucket_scale, "+")
)

level_1_counts <- level_1_data %>%
  select(date, cases_new, level_1_region) %>%
  mutate(cases_new = if_else(is.na(cases_new), 0, cases_new)) %>%
  group_by(level_1_region) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(weekly_mean_cases = roll_mean(cases_new, 7, complete_obs = TRUE)) %>%
  filter(date > "2020-10-01") %>%
  group_by(date,
    group = fct_rev(cut(weekly_mean_cases,
      breaks = bucket_breaks,
      labels = bucket_labels,
      include.lowest = TRUE
    ))
  ) %>%
  summarise(count = n())

level_1_counts %>%
  ggplot() +
  geom_col(mapping = aes(x = date, y = count, fill = group), width = 1) +
  scale_x_date(date_breaks = "2 months", date_minor_breaks = "1 month", date_labels = "%B") +
  labs(
    x = "Date",
    y = "Number of level 1 regions",
    fill = "Case count",
    title = paste0(
      tools::toTitleCase(dataset_details$level_1_region),
      " case counts in ", country
    ),
    subtitle = "7 day average counts of new cases",
    caption = caption_text
  ) +
  scale_fill_brewer(palette = "Blues", direction = 1)

ggsave(paste0("extra/", country, "-waterfall-case-counts-level-1.png"), width = 6, height = 4, units = "in")

# Waterfall chart case counts - level 2 ----
if (!is.na(dataset_details$level_2_region)) {
  # Attempt to calculate a "natural" bucket scale for the waterfalls
  bucket_scale <- median(level_2_data$cases_new, na.rm = TRUE) * 2
  if (bucket_scale < 20) {
    bucket_scale <- 20
  }
  bucket_scale <- floor(round(bucket_scale, -ceiling(log10(bucket_scale)) + 1)/20)*20
  bucket_breaks <- c(-1, seq(from = 0, to = bucket_scale, length.out = 5), Inf)
  bucket_labels <- c(
    0,
    paste(bucket_breaks[c(-1, -6, -7)],
      bucket_breaks[c(-1, -2, -7)],
      sep = "-"
    ),
    paste0(bucket_scale, "+")
  )

  level_2_counts <- level_2_data %>%
    select(date, cases_new, level_2_region) %>%
    mutate(cases_new = if_else(is.na(cases_new), 0, cases_new)) %>%
    group_by(level_2_region) %>%
    arrange(date, .by_group = TRUE) %>%
    mutate(weekly_mean_cases = roll_mean(cases_new, 7, complete_obs = TRUE)) %>%
    filter(date > "2020-10-01") %>%
    group_by(date,
      group = fct_rev(cut(weekly_mean_cases,
        breaks = bucket_breaks,
        labels = bucket_labels,
        include.lowest = TRUE
      ))
    ) %>%
    summarise(count = n())

  level_2_counts %>%
    ggplot() +
    geom_col(mapping = aes(x = date, y = count, fill = group), width = 1) +
    scale_x_date(date_breaks = "2 months", date_minor_breaks = "1 month", date_labels = "%B") +
    labs(
      x = "Date",
      y = "Number of level 2 regions",
      fill = "Case count",
      title = paste0(
        tools::toTitleCase(dataset_details$level_2_region),
        " case counts in ", country
      ),
      subtitle = "7 day average counts of new cases",
      caption = caption_text
    ) +
    scale_fill_brewer(palette = "Blues", direction = 1)

  ggsave(paste0("extra/", country, "-waterfall-case-counts-level-2.png"), width = 6, height = 4, units = "in")
}

# Waterfall chart level_1_region test positivity ----
if (!is.na(unique(level_1_data$tested_new))) {
  level_1_positivity <- level_1_data %>%
    filter(date > "2020-10-01") %>%
    # Calculate a proxy for test positivity: cases / tests
    mutate(dgn_prc_day = cases_new / tested_new * 100) %>%
    select(date, dgn_prc_day, level_1_region) %>%
    group_by(level_1_region) %>%
    arrange(date, .by_group = TRUE) %>%
    mutate(weekly_mean_positivity = roll_mean(dgn_prc_day, 7)) %>%
    group_by(date,
      group = fct_rev(cut(
        dgn_prc_day,
        breaks = c(-1, 0, 5, 10, 15, 20, Inf),
        labels = c("0%", "0-5%", "5-10%", "10-15%", "15-20%", "20%+"),
        include.lowest = TRUE
      ))
    ) %>%
    summarise(count = n())

  level_1_positivity %>%
    ggplot() +
    geom_col(mapping = aes(x = date, y = count, fill = group), width = 1) +
    scale_x_date(date_breaks = "2 months", date_minor_breaks = "1 month", date_labels = "%B") +
    labs(
      x = "Date",
      y = "Number of level 2 regions",
      fill = "Test positivity",
      title = paste0("Level 2 region test positivity in ", country),
      subtitle = "7 day average test positivity",
      caption = caption_text
    ) +
    scale_fill_brewer(palette = "Oranges", direction = 1)

  ggsave(paste0("extra/", country, "-waterfall-positivity.png"), width = 6, height = 4, units = "in")
}


# Waterfall chart level_2_region test positivity ----

if (!is.na(dataset_details$level_2_region) && !is.na(unique(level_2_data$tested_new))) {
  level_2_positivity <- level_2_data %>%
    filter(date > "2020-10-01") %>%
    # Calculate a proxy for test positivity: cases / tests
    mutate(dgn_prc_day = cases_new / tested_new * 100) %>%
    select(date, dgn_prc_day, level_2_region) %>%
    arrange(level_2_region, date) %>%
    mutate(weekly_mean_positivity = roll_mean(dgn_prc_day, 7)) %>%
    group_by(date,
      group = fct_rev(cut(
        dgn_prc_day,
        breaks = c(-1, 0, 5, 10, 15, 20, Inf),
        labels = c("0%", "0-5%", "5-10%", "10-15%", "15-20%", "20%+"),
        include.lowest = TRUE
      ))
    ) %>%
    summarise(count = n())

  level_2_positivity %>%
    ggplot() +
    geom_col(mapping = aes(x = date, y = count, fill = group), width = 1) +
    scale_x_date(date_breaks = "2 months", date_minor_breaks = "1 month", date_labels = "%B") +
    labs(
      x = "Date",
      y = "Number of level 2 regions",
      fill = "Test positivity",
      title = paste0("Level 2 region test positivity in ", country),
      subtitle = "7 day average test positivity",
      caption = caption_text
    ) +
    scale_fill_brewer(palette = "Oranges", direction = 1)

  ggsave(paste0("extra/", country, "-waterfall-positivity.png"), width = 6, height = 4, units = "in")
}

# Acceleration calculations - national ----

if (!is.na(unique(national_data$tested_new))) {
  national_data %>%
    arrange(date) %>%
    # Calculate a proxy for test positivity: cases / tests
    mutate(dgn_prc_day = cases_new / tested_new * 100) %>%
    # put rolling 7 day average in here
    mutate(
      weekly_mean_cases = roll_mean(cases_new, 7),
      weekly_mean_positivity = roll_mean(dgn_prc_day, 7)
    ) %>%
    mutate(
      cases_accel = ((weekly_mean_cases - lag(weekly_mean_cases)) / abs(lag(weekly_mean_cases))),
      test_accel = ((weekly_mean_positivity - lag(weekly_mean_positivity)) / abs(lag(weekly_mean_positivity)))
    ) %>%
    filter(date > "2020-09-01") %>%
    select(date, cases_accel, test_accel) %>%
    pivot_longer(
      cols = ends_with("_accel"),
      values_to = "accel",
      names_to = "type", names_pattern = "(.*)_accel"
    ) %>%
    mutate(type = if_else(type == "test", "test positivity", type)) %>%
    ggplot(aes(x = date, y = accel, colour = type)) +
    geom_line() +
    scale_x_date(date_breaks = "2 months", date_minor_breaks = "1 month", date_labels = "%B") +
    # scale_y_continuous(trans = modulus_trans(-0.5), labels=label_percent()) +
    scale_y_continuous(labels = label_percent()) +
    geom_hline(yintercept = 0, size = 0.2) +
    labs(
      x = "Date", y = "Acceleration",
      title = paste0("Acceleration of the COVID-19 pandemic in ", country),
      subtitle = "% change in 7-day average of incidence or test positivity",
      caption = caption_text
    )

  ggsave(paste0("extra/", country, "-acceleration-national.png"), width = 6, height = 4, units = "in")
}
