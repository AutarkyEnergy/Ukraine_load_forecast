library(MuMIn)

## set working directory and check if it is correct
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
getwd()


## load data----
## Temperature values, transformed temperature values in heating and cooling days and seasonal regressors
## (months, days) are already provided. Detailed information can be found in the associated study.

MT_deterministic_data <- read.csv("./Data/mid_deterministic_data.csv")

# make a training set until end of 2018
mid_training = MT_deterministic_data[1:2190,]


######## Find best linear models  ######## 
## PLEASE NOTE THAT CALCULATION TAKES MORE THAN 12 HOURS, RESULTS ARE ALREADY CALCULATED AND
## CAN BE LOADED IN THE NEXT SECTION.


## create global model with all midterm indicators except type of month
variables_midterm=colnames(MT_deterministic_data[,c(5:17,29:36)])

mt_formula <- as.formula(paste("mid_load", paste(variables_midterm, collapse = " + "), 
                               sep = " ~ "))

global_mid_model <- lm(mt_formula, data= mid_training,na.action="na.fail")

## create models with all combinations of all indicators
# will take a very long time - depending on the available computing power around 12-24 hours
combinations_mid <- dredge(global_mid_model)

#write.csv(combinations_mid,"./Data/midterm_combinations_final.csv",row.names = F)
# The complete file is very large and only very few models are needed, therefore 
# the file is trimmed to below 50 MB
write.csv(combinations_mid[1:200000,],"./Data/midterm_combinations_final_trimmed.csv",row.names = F)



### LOAD RESULTS IN THIS SECTION TO SKIP 12h COMPUTATION TIME  
#   Continue with evaluating the model results ----

combination_mid_final <-read.csv("./Data/midterm_combinations_final_trimmed.csv")


## manually inspect the best models (top of the list) 
# --> Models 1-4 have the same AICc, model 4 has the best predictors from an empirical point of view.  

variables_mid <- colnames(combination_mid_final[4,2:22])[complete.cases(t(combination_mid_final[4,2:22]))]

## add month variables step-wise
variables_midterm_month=colnames(MT_deterministic_data[,c(18:28)])


month_formula <- as.formula(paste("mid_load", paste(variables_midterm_month, collapse = " + "), 
                               sep = " ~ "))

model_month <- lm(month_formula, data= mid_training,na.action="na.fail")

# dredge() method is just a quick way to get the logical matrix, should go very fast
combinations_month <- dredge(model_month,trace = T)

# initiate a data frame to save the model AICc
rank_df <- as.data.frame(matrix(nrow=nrow(combinations_month),ncol = 2))
colnames(rank_df)<- c("AICc","model_no")

# calculate all combinations with month added and save AICc

for (i in 1:nrow(combinations_month)){
variables_month=colnames(combinations_month[i,2:12])[complete.cases(t(combinations_month[i,2:12]))]
variables_all= c(variables_mid,variables_month)
formula_all <- as.formula(paste("mid_load", paste(variables_all, collapse = " + "), 
                                  sep = " ~ "))
model_all <- lm(formula_all, data= mid_training,na.action="na.fail")

rank_df$AICc[i] <- AICc(model_all)
rank_df$model_no[i] <- i
}

# look at best models
best_models <- order(rank_df$AICc)

variables_best_month=colnames(combinations_month[best_models[1],2:12])[complete.cases(t(combinations_month[best_models[1],2:12]))]
variables_final= c(variables_mid,variables_best_month)
formula_final <- as.formula(paste("mid_load", paste(variables_final, collapse = " + "), 
                                sep = " ~ "))
model_final <- lm(formula_final, data= mid_training,na.action="na.fail")
save(model_final,file = "./Models/midterm_deterministic/model_final.Rdata")


### Linear regressive mid-term model is done, residuals are calculated now for the LSTM and ARIMA models 

MT <- predict(model_final,MT_deterministic_data, interval = "confidence")

residuals <- MT_deterministic_data$mid_load - MT[,1]
MT_deterministic_data$target_residuals <- residuals
MT_deterministic_data$lm_pred <- MT[,1]


### Save dataframe for LSTM script and ARIMA Calculation
write.csv(MT_deterministic_data,"./Data/midterm_ML.csv", row.names = F)
write.csv(MT_deterministic_data,"./data/midterm_det.csv", row.names = F )


###### Load machine learning LSTM results ######## 
## Note: Code for the LSTM is proprietary owned by the DLR Oldenburg, so only the output
## of the model can be made publicly availabe

LSTM_results <- read.csv("./data/midterm_LSTM_results.csv") 
MT_deterministic_data$lstm <- 0
MT_deterministic_data$lstm[2191:2920] <- LSTM_results$prediction

write.csv(MT_deterministic_data, "./data/midterm_det.csv",row.names = F)


###### ARIMA calculation ######## 
## Note: this takes very long and is already calculated, results are stored
##       in "./Data/mid_ARIMA_results.csv"


# load deterministic model and residuals
load("./Models/midterm_deterministic/model_final.Rdata")

library(tseries)
library(forecast)

res <- model_final$residuals

adf.test(res)
kpss.test(res)
# --> data is non-stationary

# double-check with auto.arima()
starting_model <- auto.arima(res)
checkresiduals(starting_model)

# --> residuals need to be differenced once to become stationary
d=1
diff_res <- diff(res,1)
acf(diff_res)  
# last significant lag at t=7  --> max grid search p-oder = 9
pacf(diff_res) 
# last significant lat at t=25 --> max grid search q-oder = 27

test_df<- data.frame(matrix(nrow=(9*27),ncol = 5))
colnames(test_df)<- c("AICC","sum_nine","sum_all","p","q")


for (k in 1:27){
  q=k
  for (i in 1:9){
    tryCatch({
    print(paste('processing ARIMA:',i,d,q))
    grid_model <- Arima(res, order = c(i, d, q))
    forecasted_arima<-forecast(grid_model, h=730,biasadj=TRUE,bootstrap = TRUE)
    test_df$AICC[((k-1)*9+i)] <- AICc(grid_model)
    res_forecasted <- forecasted_arima$mean
    res_forecasted_nine <- forecasted_arima$mean[1:9]
    res_forecasted_sum <- MT_deterministic_data$target_residuals[2191:2920] - res_forecasted

    test_df$sum_all[((k-1)*9+i)]=sum(abs(res_forecasted_sum))/sum(abs(MT_deterministic_data$target_residuals[2191:2920]))

    res_forecasted_sum_nine <- MT_deterministic_data$target_residuals[2191:2199] - res_forecasted_nine
    test_df$sum_nine[((k-1)*9+i)]=sum(abs(res_forecasted_sum_nine))/sum(abs(MT_deterministic_data$target_residuals[2191:2199]))

    test_df$p[((k-1)*9+i)] <- i
    test_df$q[((k-1)*9+i)] <- k
    
    },error=function(e){cat("ERROR :",conditionMessage(e), "\n")})
    
  }}

## If calculated write the results: 
# write.csv(test_df,"./Data/mid_ARIMA_results.csv",row.names = F )

## If not calculated load the results: 
test_df <- read.csv("./Data/mid_ARIMA_results.csv")

test_df<- test_df[is.na(test_df$sum_all)==F,]
p_order <- test_df$p[test_df$sum_all==min(test_df$sum_all)]
q_order <- test_df$q[test_df$sum_all==min(test_df$sum_all)]

best_model_mid <- Arima(res, order = c(p_order, d, q_order))

save(best_model_mid,file="./Models/midterm_stochastic/fit.mid_noreg.Rdata")


### Add linear regressors to ARIMA ----

# First test within-group deviation from uniformity and homogeneity of variances  
# of the seasonal regressors with scaled residuals from DHARMa package

library(DHARMa)
simulationOutput <- simulateResiduals(fittedModel = model_final, plot = F)

# test weekdays
 
testCategorical(simulationOutput, catPred = MT_deterministic_data$mon[1:2190])
testCategorical(simulationOutput, catPred = MT_deterministic_data$tue[1:2190])
testCategorical(simulationOutput, catPred = MT_deterministic_data$wed[1:2190])
testCategorical(simulationOutput, catPred = MT_deterministic_data$thu[1:2190])
testCategorical(simulationOutput, catPred = MT_deterministic_data$sat[1:2190])
testCategorical(simulationOutput, catPred = MT_deterministic_data$we[1:2190])


# test month

testCategorical(simulationOutput, catPred = MT_deterministic_data$jan[1:2190]) 
testCategorical(simulationOutput, catPred = MT_deterministic_data$feb[1:2190])  
testCategorical(simulationOutput, catPred = MT_deterministic_data$mar[1:2190]) 
testCategorical(simulationOutput, catPred = MT_deterministic_data$apr[1:2190])
testCategorical(simulationOutput, catPred = MT_deterministic_data$mai[1:2190])
testCategorical(simulationOutput, catPred = MT_deterministic_data$jun[1:2190]) 
testCategorical(simulationOutput, catPred = MT_deterministic_data$jul[1:2190]) 
testCategorical(simulationOutput, catPred = MT_deterministic_data$aug[1:2190])  
testCategorical(simulationOutput, catPred = MT_deterministic_data$sep[1:2190]) 
testCategorical(simulationOutput, catPred = MT_deterministic_data$okt[1:2190]) 
testCategorical(simulationOutput, catPred = MT_deterministic_data$nov[1:2190]) 

# -> weekdays seem to be completely accounted for by the deterministic model 
#    maybe adding the month as external predictors can improve the forecast 

# Try all external predictors and check for significance
load("./models/midterm_stochastic/fit.mid_noreg.Rdata")
MT_deterministic_data<-read.csv("./data/midterm_det.csv" )

grid_model_reg <- Arima(res, order = c(p_order, d, q_order),xreg = as.matrix(MT_deterministic_data[1:2190,c(18:28)]))
forecasted_arima_reg<-forecast(grid_model_reg, h=730, xreg = as.matrix(MT_deterministic_data[2191:2920,c(18:28)]) ,biasadj=TRUE,bootstrap = TRUE)
plot(forecasted_arima_reg)
summary(grid_model_reg)

# Compare with normal ARIMA forecast and LSTM forecast

forecasted_arima<-forecast(best_model_mid, h=730,biasadj=TRUE,bootstrap = TRUE)

res_forecasted <- forecasted_arima$mean
res_forecasted_lstm <-MT_deterministic_data$lstm[2191:2920]
res_forecasted_reg <- forecasted_arima_reg$mean

res_sum_arima <- sum(abs(MT_deterministic_data$target_residuals[2191:2920] - res_forecasted))
res_sum_arima
res_sum_arima_lstm <- sum(abs(MT_deterministic_data$target_residuals[2191:2920] - res_forecasted_lstm))
res_sum_arima_lstm
res_sum_arima_reg <- sum(abs(MT_deterministic_data$target_residuals[2191:2920] - res_forecasted_reg))
res_sum_arima_reg

# --> LSTM and ARIMA without external regressors still have a better forecast accuracy/lower residual sum 
# Check the residual structure visually and add a yearly sinus 

MT_deterministic_data$index <- 1:nrow(MT_deterministic_data)

t=seq(0.0172,pi*2,(pi*(2/365)))
yearly_sin <- sin(t)
plot(t,yearly_sin,type="l", xlab="time", ylab="Sine wave")
MT_deterministic_data$sin <- yearly_sin *2000

res_structure <- ggplot(MT_deterministic_data[1:2920,])+geom_line(aes(index,target_residuals,color='residuals'))+
                 geom_line(aes(index,sin))
res_structure

## --> summer time seems to still show a recurring pattern as well as the start of the year
#     summer and spring month as well as january are added step-wise to see if forecasting accuracy can 
#     be improved. 

best_model_mid_with_reg <- Arima(res, order = c(p_order, d, q_order),xreg = as.matrix(MT_deterministic_data[1:2190,c(18,22,23,24:25,26,27)]))
forecasted_arima_reg2<-forecast(best_model_mid_with_reg, h=730, xreg = as.matrix(MT_deterministic_data[2191:2920,c(18,22,23,24:25,26,27)]) ,biasadj=TRUE,bootstrap = TRUE)

res_forecasted_reg <- forecasted_arima_reg2$mean
res_sum_arima_reg <- sum(abs(MT_deterministic_data$target_residuals[2191:2920] - res_forecasted_reg))
res_sum_arima_reg
res_sum_arima_reg/sum(abs(MT_deterministic_data$target_residuals[2191:2920]))
res_sum_arima_lstm/sum(abs(MT_deterministic_data$target_residuals[2191:2920]))


# --> overall residuals with ARIMA forecast with regressors decline by about 7.2 % whereas the
#     lstm forecast only reduces the residuals by about 5.9 %

# Check forecast visually
MT_deterministic_data$arima_lstm <- c(best_model_mid_with_reg$fitted,(res_forecasted_reg+res_forecasted_lstm))
ML <- read.csv("./data/predictionnew.csv")


res_comparism <- ggplot(MT_deterministic_data[2191:2920,])+geom_line(aes(index,target_residuals,color='residuals'),lwd=1.2)+
  geom_line(aes(index, res_forecasted,color="ARIMA"),lwd=1.2)+geom_line(aes(index, res_forecasted_reg,color= "ARIMA /w reg"),lwd=1.2)+
  geom_line(aes(index,res_forecasted_lstm,color="LSTM"),lwd=1.2)+ geom_line(aes(index,ML$prediction
                                                                  ,color="ARIMA+LSTM"),lwd=1.2)+
  geom_line(aes(index,sin))
res_comparism


# Save Arima model with regressors 

save(best_model_mid_with_reg,file = "./models/midterm_stochastic/final_ARIMA_mid.Rdata")
load("./models/midterm_stochastic/final_ARIMA_mid.Rdata")

###### Save all model results ######## 

midterm_model_results <- MT_deterministic_data[,c(1:4,37,41,42,39,38,43)]
midterm_model_results$stoch <- c(best_model_mid_with_reg$fitted,res_forecasted_reg)
midterm_model_results$full_model <- midterm_model_results$lm_pred+midterm_model_results$stoch
midterm_model_results$res_full_model <- midterm_model_results$mid_load -midterm_model_results$full_model


write.csv(midterm_model_results,"./data/midterm_model_results.csv",row.names = F)

###### Plot results ######## 
library(patchwork)

# load local library for plotting
source('./ggplot_theme_Publication/ggplot_theme_Publication-2.R')

midterm_model_results <- read.csv("./data/midterm_model_results")


MTplot_overview <- ggplot(midterm_model_results)+geom_line(aes(index,mid_load,color="actual"),lwd=1.3)+
  geom_line(aes(index,lm_pred,color='fitted'),linetype=2,lwd=1.3)+
  geom_vline(xintercept=2190,linetype = 2)+
  xlab("\n Day of year") + ylab("MW\n")+
  ggtitle('Mid-term model predictions')+
  theme_Publication()+ theme(legend.title = element_blank())+
  theme(axis.title=element_text(size=26))+
  theme(legend.text=element_text(size=26))+
  theme(axis.text=element_text(size=23))+
  theme(plot.title = element_text(size=34))+
  scale_x_continuous(breaks=c(0,730,1460 , 2190), labels=c(2013,2015,2017,2019))

MTplot_overview

ggsave(file="./Plots/MTplot_overview.png", plot=MTplot_overview, width=12, height=8)


# Residual plots

MTres1<-ggplot(midterm_model_results[0:2190,]) + geom_line(aes(x = index, y =target_residuals ),lwd=1.3)+
  ggtitle(label = "Residual Plots\n") +theme_Publication()+
  ylab("MW")+xlab("Day")+
  theme(axis.title=element_text(size=26))+
  theme(legend.text=element_text(size=26))+
  theme(axis.text=element_text(size=23))+
  theme(plot.title = element_text(size=34))+
  scale_x_continuous(breaks=c(0,730,1460 , 2190), labels=c(2013,2015,2017,2019))

MTres1

MTres2<-ggAcf(midterm_model_results$target_residuals[1:2190], lag.max = 48)+ theme_Publication() +ggtitle(element_blank())+
  theme(axis.title=element_text(size=26))+
  theme(legend.text=element_text(size=26))+
  theme(axis.text=element_text(size=23))+
  theme(plot.title = element_text(size=34))

MTres2

MTres3<-ggplot(midterm_model_results[1:2190,], aes(x = target_residuals))+geom_histogram(aes(y = ..density..),binwidth = 100) +
  geom_density(color="red",lwd=1.3)+
  theme_Publication()+
  ylab("Density")+xlab("MW")+
  theme(axis.title=element_text(size=26))+
  theme(legend.text=element_text(size=26))+
  theme(axis.text=element_text(size=23))+
  theme(plot.title = element_text(size=34))

MTres3


## Arrange residual plots

MTresiduals<-MTres1 /(MTres2+MTres3)
MTresiduals

ggsave(file="./Plots/MTplot_residuals.png", plot=MTresiduals, width=12, height=8)





##### Delete ---------




LTmodel_starting_data <- read.csv("./data/LTmodel_starting_data.csv")


MT_deterministic_data[,43:60]<-0
colnames(MT_deterministic_data)[43:60]  <-colnames(LTmodel_starting_data[2:19])

colnames(MT_deterministic_data)[43] 
for (i in 2013:2020){
  MT_deterministic_data[MT_deterministic_data$year==i,43:60]<-LTmodel_starting_data[LTmodel_starting_data$year==i,2:19]
}

unique(MT_deterministic_data$Manuf_value)
write.csv(MT_deterministic_data,"./data/ML_df_final23.csv",row.names = F)
