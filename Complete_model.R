## Set working directory and check it
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
getwd()

# load local library for plotting
source('./ggplot_theme_Publication/ggplot_theme_Publication-2.R')

###### Prepare data ######


all_results <- read.csv("./data/complete_dataframe.csv")
longterm_model_results <- read.csv("./data/longterm_model_results.csv")
midterm_model_results <- read.csv("./data/midterm_model_results.csv")
all_results_shortterm <- read.csv("./Data/all_results_shortterm.csv")


all_results$longterm_det <- 0

for (i in 2013:2020){
  all_results$longterm_det[all_results$year==i] <- longterm_model_results$fitted[longterm_model_results$year==i] 
}

all_results$midterm_det <- 0
all_results$midterm_Arima <- 0
all_results$midterm_LSTM <- 0

k=1
for (i in 1:nrow(midterm_model_results)){
  all_results$midterm_det[k:(k+23)] <- midterm_model_results$lm_pred[i]
  all_results$midterm_Arima[k:(k+23)] <- midterm_model_results$stoch[i]
  all_results$midterm_LSTM[k:(k+23)] <- midterm_model_results$lstm[i]
  
  k=k+24
}

all_results$shortterm_det <- all_results_shortterm$deterministic_fitted
all_results$shortterm_stoch <- all_results_shortterm$stoch


all_results$complete_model <- all_results$longterm_det+ all_results$midterm_det+ all_results$midterm_Arima+
                              all_results$shortterm_det+ all_results$shortterm_stoch

write.csv(all_results,"./data/final_results_df.csv",row.names = F)



##### Error metrics #####

library(MLmetrics)

#Training set
MAPE(all_results$complete_model[26281:70080], all_results$actual[26281:70080])
MAE(all_results$complete_model[26281:70080], all_results$actual[26281:70080])
RMSE(all_results$complete_model[26281:70080], all_results$actual[26281:70080])

#All Test set
MAPE(all_results$complete_model[52561:70080], all_results$actual[52561:70080])
MAE(all_results$complete_model[52561:70080], all_results$actual[52561:70080])
RMSE(all_results$complete_model[52561:70080], all_results$actual[52561:70080])

#2019
MAPE(all_results$complete_model[52561:61320], all_results$actual[52561:61320])
MAE(all_results$complete_model[52561:61320], all_results$actual[52561:61320])
RMSE(all_results$complete_model[52561:61320], all_results$actual[52561:61320])

#2020
MAPE(all_results$complete_model[61321:70080], all_results$actual[61321:70080])
MAE(all_results$complete_model[61321:70080], all_results$actual[61321:70080])
RMSE(all_results$complete_model[61321:70080], all_results$actual[61321:70080])


