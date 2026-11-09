#Project
old_loc = Sys.getlocale("LC_TIME")
Sys.setlocale("LC_TIME", "C")

library(lubridate)
library(tidyverse)
library(tseries)
library(uroot)
library(urca)
library(zoo)
library(forecast)
library(scales)

data = read.csv("data/Project.csv", sep = ";", fileEncoding = "UTF-8-BOM")
str(data)

data = data %>% rename(Gross_production_of_electricity_in_GWh = Gross.production.of.electricity.in.GWh)

data$Date = as.yearmon(data$Date, "%Y-%m")

str(data)

#graph
ggplot(data = data, aes(x = Date, y = Gross_production_of_electricity_in_GWh)) +
  geom_line(color = "darkblue", linewidth = 0.5) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank()
  )

#stationarity tests
summary(ur.df(data$Gross_production_of_electricity_in_GWh, type = c("drift"), selectlags = "BIC"))

#stationary at levels


#For logs
data = data %>% 
  mutate(ln_Gross_production_of_electricity_in_GWh = log(Gross_production_of_electricity_in_GWh)) 

ggplot(data = data, aes(x = Date, y = ln_Gross_production_of_electricity_in_GWh)) +
  geom_line(color = "darkblue", linewidth = 0.5) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank()
  )

summary(ur.df(data$ln_Gross_production_of_electricity_in_GWh, type = c("drift"), selectlags = "BIC"))


#Train/Test split
y = ts(
  data$Gross_production_of_electricity_in_GWh,
  start = c(2001, 1),
  frequency = 12
)


n = length(y)
n
h = ceiling(0.20*n) #test size
h

train = window(y, end = time(y)[n - h])
test  = window(y, start = time(y)[n - h + 1])

length(train)
length(test)
start(test)

#HEGY test for seasonal unit roots
summary(hegy.test(train, deterministic = c(1,0,1), lag.method = "BIC"))


train_log = log(train)

summary(hegy.test(train_log, deterministic = c(1,0,1), lag.method = "BIC"))

#ACF/PACF
par(mfrow = c(1, 2))
acf(train_log, lag.max = 48, main = "ACF (Train)")
pacf(train_log, lag.max = 48, main = "PACF (Train)")
par(mfrow = c(1, 1))

#ARIMA
fit1 = arima(
  train_log,
  order = c(1, 0, 0),
  seasonal = list(order = c(1, 0, 1), period = 12)
)

fit2 = arima(
  train_log,
  order = c(1, 0, 1),
  seasonal = list(order = c(1, 0, 1), period = 12)
)

fit3 = arima(
  train_log,
  order = c(0, 0, 1),
  seasonal = list(order = c(1, 0, 1), period = 12)
)

BIC(fit1, fit2, fit3)
#fit1 - lowest BIC

checkresiduals(fit1)
#No autocorrelation - we cannot reject the H0


fitted_log = fitted(fit1)
fitted_level = exp(fitted_log)

train_time = time(train)

fitted_ts = ts(
  fitted_level,
  start = train_time[length(train_time) - length(fitted_level) + 1],
  frequency = 12
)

df_plot = data.frame(
  Date = as.yearmon(time(train)),
  Actual = as.numeric(train),
  Fitted = c(rep(NA, length(train) - length(fitted_ts)), as.numeric(fitted_ts))
)

ggplot(df_plot, aes(x = Date)) +
  geom_line(aes(y = Actual), color = "black", linewidth = 0.6) +
  geom_line(aes(y = Fitted), color = "red", linewidth = 0.8) +
  labs(
    title = "SARIMA(1,0,0)(1,0,1)[12] — Fit on Training Data",
    y = "Gross production of electricity (GWh)",
    x = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())


#Now with test
fc_log = forecast(fit1, h = length(test))

fc_level = exp(fc_log$mean)

df_test_plot = data.frame(
  Date = as.yearmon(c(time(train), time(test))),
  Actual = c(as.numeric(train), as.numeric(test)),
  Forecast = c(
    rep(NA, length(train)),
    as.numeric(fc_level)
  )
)

ggplot(df_test_plot, aes(x = Date)) +
  geom_line(aes(y = Actual), color = "black", linewidth = 0.6) +
  geom_line(aes(y = Forecast), color = "red", linewidth = 0.8) +
  geom_vline(
    xintercept = as.yearmon(time(test)[1]),
    linetype = "dashed",
    color = "grey40"
  ) +
  labs(
    title = "SARIMA(1,0,0)(1,0,1)[12] — Out-of-Sample Forecast",
    subtitle = "Dashed line = start of test sample",
    y = "Gross production of electricity (GWh)",
    x = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())

accuracy(fc_level, test)

#I need to add a dummy for Covid

xreg = ifelse(time(train) >= 2020, 1, 0)

fit_x = arima(
  train_log,
  order = c(1, 0, 0),
  seasonal = list(order = c(1, 0, 1), period = 12),
  xreg = xreg
)

summary(fit_x)
checkresiduals(fit_x)


df = length(train_log) - length(coef(fit_x))
df

t_stat_ar1 = 0.6798/0.0492
p_value_ar1 = 2 * (1 - pt(abs(t_stat_ar1), df))
p_value_ar1 #0

t_stat_sar1 =  0.9925/0.0054   
p_value_sar1 = 2 * (1 - pt(abs(t_stat_sar1), df))
p_value_sar1 #0

t_stat_sma1 =   -0.8236/0.0572        
p_value_sma1 = 2 * (1 - pt(abs(t_stat_sma1), df))
p_value_sma1 #0

t_stat_int =   8.2103/0.0754           
p_value_int = 2 * (1 - pt(abs(t_stat_int), df))
p_value_int #0

t_stat_dum =   -0.0730/0.0438           
p_value_dum = 2 * (1 - pt(abs(t_stat_dum), df))
p_value_dum #0.09693013



xreg_train = ifelse(time(train) >= 2020, 1, 0)

fit_x2 = Arima(
  train_log,
  order = c(1, 0, 0),
  seasonal = c(1, 0, 1),
  xreg = xreg_train,
  include.mean = TRUE
)


summary(fit_x2)
checkresiduals(fit_x2)


xreg_test = ifelse(time(test) >= 2020, 1, 0)

fc_x_log = forecast(fit_x2, xreg = xreg_test, h = length(test))
fc_x = exp(fc_x_log$mean)
accuracy(fc_x, test)

df_test_plot_x = data.frame(
  Date = as.yearmon(c(time(train), time(test))),
  Actual = c(as.numeric(train), as.numeric(test)),
  Forecast = c(rep(NA, length(train)), as.numeric(fc_x))
)

ggplot(df_test_plot_x, aes(Date)) +
  geom_line(aes(y = Actual), color = "black", linewidth = 0.6) +
  geom_line(aes(y = Forecast), color = "blue", linewidth = 0.8) +
  geom_vline(xintercept = as.yearmon(time(test)[1]), linetype = "dashed") +
  labs(
    title = "SARIMAX with COVID Dummy — Test Sample Forecast",
    y = "GWh",
    x = NULL
  ) +
  theme_minimal()

acc_sarima  = accuracy(fc_level, test)
acc_sarimax = accuracy(fc_x, test)

rbind(
  SARIMA  = acc_sarima[1, c("RMSE","MAE","MAPE","ACF1","Theil's U")],
  SARIMAX = acc_sarimax[1, c("RMSE","MAE","MAPE","ACF1","Theil's U")]
)

y_full = ts(data$Gross_production_of_electricity_in_GWh, start=c(2001,1), frequency=12)
xreg_full = ifelse(time(y_full) >= 2020, 1, 0)

final_fit = Arima(log(y_full), order=c(1,0,0), seasonal=c(1,0,1), xreg=xreg_full)

# Fitted values (on log scale → back to levels)
fitted_full = exp(fitted(final_fit))

df_fit = data.frame(
  Date = as.yearmon(time(y_full)),
  Actual = as.numeric(y_full),
  Fitted = as.numeric(fitted_full)
)


ggplot(df_fit, aes(Date)) +
  geom_line(aes(y = Actual), color = "black", linewidth = 0.6) +
  geom_line(aes(y = Fitted), color = "blue", linewidth = 0.8) +
  labs(
    title = "Final SARIMAX Fit vs Actual Data",
    subtitle = "In-sample fit on full dataset",
    y = "Gross production of electricity (GWh)",
    x = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())



df_test_plot_final = df_test_plot %>%
  rename(SARIMA_Forecast = Forecast) %>%
  mutate(SARIMAX_Forecast = df_test_plot_x$Forecast)


forecast_plot = ggplot(df_test_plot_final, aes(Date)) +
  geom_line(aes(y = Actual), color = "black", linewidth = 0.6) +
  geom_line(aes(y = SARIMA_Forecast), color = "red", linewidth = 0.8) +
  geom_line(aes(y = SARIMAX_Forecast), color = "blue", linewidth = 0.8) +
  labs(
    title = "SARIMA vs SARIMAX Forecast Comparison",
    subtitle = "In-sample fir on full dataset",
    y = "Gross production of electricity (GWh)",
    x = "Date"
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())


ggsave("output/figures/forecast_test_sample.png", plot = forecast_plot,
       width = 9, height = 5, bg = "white", dpi = 150)
  

