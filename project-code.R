###################################################################

### Title: Group project Statistics & Methodology
### Group: 29
### Members:
#   - Chi Hung (SNR: 2034109, ANR: u677127)
#   - Estée Coenraad (SNR: 2013242, ANR: u225986)
#   - Martijn Hooijman (SNR: 2034200, ANR: u996412)
#   - Sathya Krishna Sharma Jagannatha (SRN: 2033987, ANR: u580435)

###################################################################


# Clear workspace
rm(list = ls(all = TRUE))

# Loading packages.
library(mice) # For missing data descriptives
library(miceadds)
library(MASS) # For robust stats
library("dplyr")
library(MLmetrics)

source("./helpers/miPredictionRoutines.R")

# Set seed
seed = 235711
set.seed(seed)


########################
### Data preparation ###
########################

# Load data
dataDir  = "../data/"
fileName = "wvs_data.rds"
data = readRDS(paste0(dataDir, fileName))

# Select features from full dataset
dataV <-data %>% select(V7,V8,V10,V11,V23,V24,V45,V46,V48,V53,V55,V59,V60,V81,V96,V97,V121,V123,V139,V143,V181,V239,V248,V242,V240)

summary(dataV)
str(dataV)
names(dataV)

# Removing all the negative values.
dataV[dataV<0] <- NA



### Univariate outlier treatment.

# Function to detect univariate outliers using the boxplot method
bpOutliers <- function(x) {
  ## Compute inner and outer fences:
  iFen <- boxplot.stats(x, coef = 1.5)$stats[c(1, 5)]
  oFen <- boxplot.stats(x, coef = 3.0)$stats[c(1, 5)]
  
  ## Return the row indices of flagged 'possible' and 'probable' outliers:
  list(possible = which(x < iFen[1] | x > iFen[2]),
       probable = which(x < oFen[1] | x > oFen[2])
  )
}

# Detect univariate outliers
uni_outliers <- lapply(dataV, FUN = bpOutliers)

# Print variables with the number of univariate outliers if more than 0
uni_outliers_sum = lapply(uni_outliers, FUN=lengths)
uni_outliers_sum[uni_outliers_sum > 0]
for(name in names(uni_outliers_sum)) {
  if(uni_outliers_sum[name][[1]] > 0) {
    print(uni_outliers_sum[name])
  }
}

# Function to remove probable univariate outliers
out_clean <- function(y){
  indx=uni_outliers$y$probable
  dataV[indx, y] <- NA  
}

# Remove probable univariate ourliers from data
for (i in names(dataV)){
  out_clean(i)
}


### Missing data

cm <- colSums(is.na(dataV))
pm <- colMeans(is.na(dataV))

## Summarize proportion of missing data:
range(pm)
mean(pm)
median(pm)

## Find variables with PM greater than 10%:
pm[pm > 0.1]

## Compute covariance coverage:
cc <- md.pairs(dataV)$rr / nrow(dataV)

## Range of covariance coverages of all variables:
range(cc)


### Multile Imputation for missing values

# Convert binary and nominal variables into factors
dataV$V24 <- as.factor(dataV$V24)
dataV$V240 <- as.factor(dataV$V240)
dataV$V248 <- as.factor(dataV$V248)
dataV$V60 <- as.factor(dataV$V60)
dataV$V81 <- as.factor(dataV$V81)

# Define our own method vector:
meth <- rep("norm", ncol(dataV))
names(meth) <- colnames(dataV)

meth["V24"]    <- "logreg"
meth["V240"]    <- "logreg"
meth["V248"] <- "polyreg"
meth["V60"] <- "polyreg"
meth["V81"] <- "polyreg"
meth["V242"]<- "norm"

## Use mice::quickpred to generate a predictor matrix:
predMat <- quickpred(dataV, mincor = 0.2, include = "V240")  # using variable V240 (gender) as a predictor always
#predMat <- ?quickpred(bfi, mincor = 0.2)

## Impute missing using the predictor matrix from above:
miceOut <- mice(data            = dataV,
                m               = 20,
                maxit           = 10,
                method          = meth,
                predictorMatrix = predMat,
                seed            = seed)

summary(miceOut)

# Select only non categorical or binary variables to perform multivariate outlier analysis
miceOut2 <-
  subset_datlist(datlist = miceOut,
                 select  = setdiff(colnames(dataV), c("V24", "V240","V248","V60","V81")),
                 toclass = "mids")

# Create list of multiply imputed datasets:
impList <- complete(miceOut2, "all")

# Function to obtain multivariate outliers using the Mahalanobis Squared distances method
mdOutliers <- function(data, critProb, statType = "mcd", ratio = 0.75, seed = NULL)
  {
    ## Set a seed, if one is provided:
    if(!is.null(seed)) set.seed(seed)
    
    ## Compute (robust) estimates of the mean and covariance matrix:
    stats <- cov.rob(x             = data,
                     quantile.used = floor(ratio * nrow(data)),
                     method        = statType)
    
    ## Compute robust squared Mahalanobis distances
    md <- mahalanobis(x = data, center = stats$center, cov = stats$cov)
    
    ## Find the cutoff value:
    crit <- qchisq(critProb, df = ncol(data))
    
    ## Return row indices of flagged observations:
    which(md > crit)
  }

# Find multivariate outliers with a critical probability of 0.99
olList <- lapply(impList, mdOutliers, critProb = 0.99, seed = seed)

# Count the number of times each observation is flagged as an outlier:
olCounts <- table(unlist(olList))

# Define the threshold for voting (will be 10 in this case):
thresh <- ceiling(miceOut$m / 2)

# Define a vector of row indices for outliers:
outs <- as.numeric(names(olCounts[olCounts >= thresh]))

# Exclude outlying observations from mids object:
miceOut3 <- subset_datlist(datlist = miceOut, # We're using the original imputations
                           subset  = setdiff(1 : nrow(dataV), outs),
                           toclass = "mids")


## Sanity check the imputations by plotting observed vs. imputed densities:
densityplot(miceOut3)

impList2 <- complete(miceOut3, "all")



############################
### Predictive Modelling ###
############################

# Select variables used for predictive modelling
variable_names = c('V10', 'V11', 'V23', 'V24', 'V55', 'V59', 'V143', 'V181', 'V248')
select_columns = function(list) {
  return(list[variable_names])
}

imp_data = lapply(impList2, select_columns)  # Imputed dataset for further use

# Split data into train and test partitions
n = nrow(imp_data[[which.max(lapply(imp_data, nrow))]])  # Number of rows in 
n_train = ceiling(n * 0.8)
n_test = n-n_train
index <- sample(
  c( rep("train", n_train), rep("test", n_test)) 
)

imp_data_splitted = splitImps(imps = imp_data, index = index)  # Splitted imputed dataset


### Predictive model selection

# Function to generate a list of model strings based on its input
# Models are formed as follows:
#    out ~ chosen +/* new[1]
#    out ~ chosen +/* new[2]
#    out ~ chosen +/* new[n]
get_models = function(out, chosen, new, interaction = FALSE) {
  '
  Returns the current model + new tryouts as strings  
  '
  models = c()
  base_model = out
  sep = ' ~ '
  
  if(!is.null(chosen)) {
    var_string = NULL
    for(chosen_var in chosen) {
      if(is.null(var_string)) {
        var_string = chosen_var
      } else {
        if (interaction) {
          var_string = paste(var_string, chosen_var, sep=" * ")
        } else {
          var_string = paste(var_string, chosen_var, sep=" + ")
        }
      }
    }
    base_model = paste(base_model, var_string, sep = sep)
    
    if(interaction) {
      sep = ' * '
    } else {
      sep = ' + '
    }
  }
  
  for(var in new) {
    models = c(models, paste(base_model, var, sep = sep))
  }
  
  return(models)
}

# Loop to try out the different models and keep selecting the best addition if significant.
# record the best model definition and cross validation error

# Function to test models using 10-fold cross validation. Starting with the simpelest sef of models:
#    outcome_var ~ predictor_vars[1]
#    outcome_var ~ predictor_vars[2]
#    outcome_var ~ predictor_vars[n]
# The best model is selected from this set by searching for the lowest cross validation error.
# Next, a new set of models is obtained using the best model, extended with the remaining variables.
# This process continues untill the cross validation error does no longer decrease.
select_model <- function(interaction = FALSE, verbose = TRUE) {
  outcome_var = 'V23'
  predictor_vars = variable_names[!variable_names == outcome_var]  # All variables except the ourcome variable V23
  chosen_vars = NULL
  
  best_model = ""  # Holds the best model's definition
  best_cve = 9999  # Holds the best model's cross validation error
  
  found_significant_improvement = TRUE  # As long as this variable is TRUE, the loop continues looking for a better model.
  while(found_significant_improvement) {  # Start testing models
    
    if(verbose) cat('-------------------------------------------------------\n\n', sep = '\n')
    
    # get models 
    models = get_models(outcome_var, chosen_vars, predictor_vars, interaction = interaction)  # Obtain a list of model definition strings
    
    if(verbose) cat('Testing models:\n', models, sep = '\n')
    
    ## Conduct 10-fold cross-validation in each multiply imputed dataset:
    tmp <- sapply(imp_data_splitted$train, cv.lm, K = 10, models = models, seed = seed)  # Fit the models to the train data and conduct 10-fold cross validation
    
    ## Aggregate the MI-based CVEs:
    if(length(predictor_vars) == 1) {  # Only one model is fitted
      cve <- mean(tmp)
      
      # Select the best model's definition and cross validation error
      min_cve = mean(tmp)
      min_cve_model = models[[1]]
      
    } else {  # Multiple models are fitted
      cve <- rowMeans(tmp)
      
      # Select the best model's definition and cross validation error
      min_cve = min(cve)
      min_cve_model = which.min(cve)
      min_cve_model = names(min_cve_model)[[1]]
    }
    
    if(verbose) cat('\nResulting CVE\'s:\n', cve, '\n')
    
    if(min_cve < best_cve) {  # Check if the cross validation error of best model from the current set is lower than the current best model
      
      # Save results outside while loop
      best_cve = min_cve
      best_model = min_cve_model
      
      if(verbose) cat('\nNew best model found:', best_model, '( cve: ', min_cve, ').\n\n')
      
      # Update chosen_vars and new variable vectors
      model_splitted = strsplit(best_model, "\\~|\\ + |\\ * ")[[1]]
      winning_var = model_splitted[[length(model_splitted)]]
      chosen_vars = c(chosen_vars, winning_var)
      predictor_vars = predictor_vars[!predictor_vars == winning_var]
      
      # End loop if no predictor vars are left
      if(length(predictor_vars) == 0) {
        found_significant_improvement = FALSE
      }
      
    } else {
      # End loop if no improvement was found
      found_significant_improvement = FALSE
    }
    
    if(found_significant_improvement == FALSE && verbose) cat('\nNo improvements found.\n-------------------------------------------------------\n\nBest model: ', best_model, '( cve:', best_cve, ').\n')
    
  }
  
  return(c(best_model, best_cve))
  
}


best_model_no_interaction <- select_model(interaction = FALSE)  # Find the best model without interaction
best_model_interaction <- select_model(interaction = TRUE)  # Find the best model with interaction


# Find the model definition with the lowest CVE
if(best_model_no_interaction[2] < best_model_interaction[2]) {
  best_model = best_model_no_interaction
} else {
  best_model = best_model_interaction
}

cat('Model with the lowest CVE:', best_model[1], "with CVE of ", best_model[2], '\n', sep=" ")


## Refit the winning model and compute test-set MSEs:
fits <- lapply(X   = imp_data_splitted$train,
               FUN = function(x, mod) lm(mod, data = x),
               mod = best_model[1])
mse <- mseMi(fits = fits, newData = imp_data_splitted$test)

cat('MSE on test set for the selected model (', best_model[1], '):', mse, sep = ' ')



#############################
### Inferential Modelling ###
#############################

### General hypothesis

# H0:Gender politics relate to economic beliefs
# H1:Gender politics does not relate to economic beliefs


### Sub H0: Gender politics does play a role in job scarcity

# Regression models
fit1.1 <-lm.mids(V45 ~ V7,data = miceOut3)
fit1.2 <-lm.mids(V45 ~ V7+ V48,data = miceOut3)
fit1.3 <-lm.mids(V45 ~ V7+ V53,data = miceOut3)
fit1.4 <-lm.mids(V45 ~ V7+ +V48 + V53,data = miceOut3)

# Summarize the model
sf1.1 <- summary(fit1.1)
sf1.2 <- summary(fit1.2)
sf1.3 <- summary(fit1.3)
sf1.4 <-summary(fit1.4)

# Pooled the fitted model
poolsf1.1 <- pool(fit1.1)
poolsf1.2 <- pool(fit1.2)
poolsf1.3 <- pool(fit1.3)
poolsf1.4 <- pool(fit1.4)

# Summarize the pooled estimates
summary(poolsf1.1)
summary(poolsf1.2)
summary(poolsf1.3)
summary(poolsf1.4)

# Pooled R Squared
pool.r.squared(fit1.1)
pool.r.squared(fit1.2)
pool.r.squared(fit1.3)
pool.r.squared(fit1.4)

# Pooled Adj.R Squared 
pool.r.squared(fit1.1, adjusted = TRUE)
pool.r.squared(fit1.2, adjusted = TRUE)
pool.r.squared(fit1.3, adjusted = TRUE)
pool.r.squared(fit1.4, adjusted = TRUE)

# Compute increase in R^2
pool.r.squared(fit1.2)[1] - pool.r.squared(fit1.1)[1]
pool.r.squared(fit1.3)[1] - pool.r.squared(fit1.2)[1]
pool.r.squared(fit1.4)[1] - pool.r.squared(fit1.3)[1]

# Significant increase in R^2? F Statistics
anova(fit1.1, fit1.2)
anova(fit1.1, fit1.2,fit1.3)
anova(fit1.1, fit1.2,fit1.3,fit1.4)


### Sub H0: Gender politics does not relate to income inequality

# Regression model
fit2.1 <-lm.mids(V96 ~ V240, data = miceOut3)
fit2.2 <-lm.mids(V96 ~ V240+V45, data = miceOut3)
fit2.3 <-lm.mids(V96 ~ V240+V45+V7, data = miceOut3)
fit2.4 <-lm.mids(V96 ~ V240+V45+V7+V139,data = miceOut3)

# Summarize the model
sf2.1 <- summary(fit2.1)
sf2.2 <- summary(fit2.2)
sf2.3 <- summary(fit2.3)
sf2.4 <- summary(fit2.4)

# Pooled the fitted model
poolsf2.1 <- pool(fit2.1)
poolsf2.2 <- pool(fit2.2)
poolsf2.3 <- pool(fit2.3)
poolsf2.4 <- pool(fit2.4)

# Summarize the pooled estimates
summary(poolsf2.1)
summary(poolsf2.2)
summary(poolsf2.3)
summary(poolsf2.4)

# Pooled R Squared
pool.r.squared(fit2.1)
pool.r.squared(fit2.2)
pool.r.squared(fit2.3)
pool.r.squared(fit2.4)

pool.r.squared(fit2.1, adjusted = TRUE)
pool.r.squared(fit2.2, adjusted = TRUE)
pool.r.squared(fit2.3, adjusted = TRUE)
pool.r.squared(fit2.4,adjusted = TRUE)

# Compute increase in R^2
pool.r.squared(fit2.2)[1] - pool.r.squared(fit2.1)[1]
pool.r.squared(fit2.3)[1] - pool.r.squared(fit2.2)[1]
pool.r.squared(fit2.4)[1] - pool.r.squared(fit2.3)[1]

# Significant increase in R^2?
anova(fit2.1, fit2.2)
anova(fit2.1, fit2.2, fit2.3)
anova(fit2.1, fit2.2, fit2.3, fit2.4)


### Sub H0: Economic belief is related to the importance of economic growth

# Regression model
fit3.1 <-lm.mids(V8 ~ V81, data = miceOut3)
fit3.2 <-lm.mids(V8 ~ V81 + V121, data = miceOut3)
fit3.3 <-lm.mids(V8 ~ V81 + V121 +V97, data = miceOut3)
fit3.4 <-lm.mids(V8 ~ V81 + V121 + V97 + V239, data = miceOut3)

# Summarize the model
sf3.1 <- summary(fit3.1)
sf3.2 <- summary(fit3.2)
sf3.3 <- summary(fit3.3)
sf3.4 <- summary(fit3.4)

# Pooled the fitted model
poolsf3.1 <- pool(fit3.1)
poolsf3.2 <- pool(fit3.2)
poolsf3.3 <- pool(fit3.3)
poolsf3.4 <- pool(fit3.4)

# Summarize the pooled estimates:
summary(poolsf3.1)
summary(poolsf3.2)
summary(poolsf3.3)
summary(poolsf3.4)

# Pooled R Squared
pool.r.squared(fit3.1)
pool.r.squared(fit3.2)
pool.r.squared(fit3.3)
pool.r.squared(fit3.4)

pool.r.squared(fit3.1, adjusted= TRUE)
pool.r.squared(fit3.2, adjusted = TRUE)
pool.r.squared(fit3.3, adjusted =TRUE)
pool.r.squared(fit3.4, adjusted = TRUE)

# Compute increase in R^2
pool.r.squared(fit3.2)[1] - pool.r.squared(fit3.1)[1]
pool.r.squared(fit3.3)[1] - pool.r.squared(fit3.2)[1]
pool.r.squared(fit3.4)[1] - pool.r.squared(fit3.3)[1]

# Significant increase in R^2?
anova(fit3.1, fit3.2)
anova(fit3.1, fit3.2, fit3.3)
anova(fit3.1, fit3.2, fit3.3, fit3.4)


### Sub H0: Gender politics does not relate if losing my job is important

# Regression model
fit4.1 <-lm.mids(V181 ~ V45, data = miceOut3)
fit4.2 <-lm.mids(V181 ~ V45 + V240, data = miceOut3)
fit4.3 <-lm.mids(V181 ~ V45 + V240+ V8, data = miceOut3)

# Summarize the fitted model
sf4.1 <-summary(fit4.1)
sf4.2 <-summary(fit4.2)
sf4.3 <-summary(fit4.3)

# Pooled the model
poolsf4.1 <- pool(fit4.1)
poolsf4.2 <- pool(fit4.2)
poolsf4.3 <- pool(fit4.3)

# Summarize the pooled estimates:
summary(poolsf4.1)
summary(poolsf4.2)
summary(poolsf4.3)

# Pooled R Squared
pool.r.squared(fit4.1)
pool.r.squared(fit4.2)
pool.r.squared(fit4.3)

pool.r.squared(fit4.1, adjusted= TRUE)
pool.r.squared(fit4.2, adjusted= TRUE)
pool.r.squared(fit4.3, adjusted= TRUE)

# Compute increase in R^2
pool.r.squared(fit4.2)[1] - pool.r.squared(fit4.1)[1]
pool.r.squared(fit4.3)[1] - pool.r.squared(fit4.2)[1]

#Significant increase in R^2?
anova(fit4.1, fit4.2)
anova(fit4.1, fit4.2, fit4.3)

