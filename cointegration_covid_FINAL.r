# Load required libraries
library(urca)
library(forecast)
library(tidyverse)
library(vars)
library(lmtest)
library(ggplot2)
library(tseries)
library(openxlsx)

# Define file paths
input_directory <- "./iCompBio/covid-cointegration-summer2021/input/county3RWM"
output_file <- './iCompBio/covid-cointegration-summer2021/output/test_export.xlsx'

# Function to import and preprocess CSV data
load_and_preprocess_data <- function(directory) {
  files <- list.files(directory, pattern = ".csv", full.names = TRUE)
  data_list <- lapply(files, function(file) {
    df <- read.csv(file)
    df[is.na(df)] <- 0
    return(df)
  })
  names(data_list) <- gsub(".csv", "", basename(files))
  names(data_list) <- gsub(", ", "-", names(data_list))
  return(data_list)
}

# Function to create time series objects
create_time_series <- function(data, column_name) {
  ts(data[[column_name]], start = 1, end = 248, frequency = 1)
}

# Function to set lag values, ensuring a minimum lag of 2
adjust_lag_values <- function(lag_vals) {
  pmax(lag_vals, 2)
}

# Function to perform Johansen test with error handling
perform_johansen_test <- function(system, k_val) {
  tryCatch(
    ca.jo(system, type = 'trace', ecdet = 'const', K = k_val),
    error = function(e) {
      message("Error in Johansen test: ", e$message)
      NULL
    }
  )
}

# Load data
data_list <- load_and_preprocess_data(input_directory)

# Initialize results data frame
results_df <- data.frame(
  Location = character(),
  `Start Date` = character(),
  `End Date` = character(),
  `Test ID` = character(),
  `Test Type` = character(),
  `Test Statistic` = numeric(),
  `0.05 Critical Value` = numeric(),
  `P Value` = numeric(),
  stringsAsFactors = FALSE
)

# Loop through each dataset for analysis
for (i in 1:length(data_list)) {
  data <- data_list[[i]]
  title <- names(data_list)[i]
  
  # Create time series
  time_series <- list(
    DC = create_time_series(data, "dailyCases"),
    AT = create_time_series(data, "air_temp"),
    RH = create_time_series(data, "RH"),
    Rt = create_time_series(data, "Rt"),
    AD = create_time_series(data, "AppleDriving"),
    GW = create_time_series(data, "GoogleWorkplace"),
    GR = create_time_series(data, "GoogleResidential")
  )
  
  # Define VAR systems
  systems <- list(
    system1 = cbind(time_series$Rt, time_series$AT),
    system2 = cbind(time_series$Rt, time_series$RH),
    system3 = cbind(time_series$Rt, time_series$AD),
    system4 = cbind(time_series$Rt, time_series$GW),
    system5 = cbind(time_series$Rt, time_series$GR)
  )
  
  # Determine optimal lag length
  k_vals <- sapply(systems, function(sys) {
    lag_select <- VARselect(sys, lag.max = 7, type = "const")
    as.integer(names(sort(summary(as.factor(lag_select$selection)), decreasing = TRUE)[1])) - 1
  })
  k_vals <- adjust_lag_values(k_vals)
  
  # Perform Johansen tests and collect results
  for (j in 1:5) {
    system_name <- paste0("system", j)
    johansen_test_result <- perform_johansen_test(systems[[system_name]], k_vals[j])
    
    if (is.null(johansen_test_result)) next
    
    # Calculate ADF test p-value
    adf_test <- adf.test(time_series$Rt - abs(johansen_test_result@V[2,1]) * time_series[[names(time_series)[j+1]]] + abs(johansen_test_result@V[3,1]])
    
    # Store test results
    results_df <- rbind(results_df, data.frame(
      Location = title,
      `Start Date` = min(data$date),
      `End Date` = max(data$date),
      `Test ID` = c("Air Temperature", "RH", "Apple Driving", "Google Workplace", "Google Residential")[j],
      `Test Type` = johansen_test_result@type,
      `Test Statistic` = johansen_test_result@teststat[2],
      `0.05 Critical Value` = johansen_test_result@cval[2,2],
      `P Value` = adf_test$p.value,
      stringsAsFactors = FALSE
    ))
  }
}

# Write results to Excel file
write.xlsx(results_df, output_file, overwrite = TRUE)
