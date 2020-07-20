### Title:    Process Wave 6 WVS Data
### Author:   Kyle M. Lang
### Created:  2018-09-18
### Modified: 2020-02-10

### Inputs:
## 1) dataDir:  The relative path to the directory containing your data
## 2) fileName: The file name (including extension) of the Wave 6 WVS RDS file

### Output:
## 1) A processed dataset called "wvs_data.rds" saved to the directory assigned 
##    to the "dataDir" variable


dataDir  <- "../data/"
outDir   <- "../output/"
fileName <- "wv6_data.rds"
###--END USER INPUT----------------------------------------------------------###

## Ensure that data directory includes a trailing slash:
lastChar <- substr(dataDir, start = nchar(dataDir), stop = nchar(dataDir))
if(lastChar != "/") dataDir <- paste0(dataDir, "/")

## Load the target variable names:
varNames <- readRDS(paste0(dataDir, "wvs_column_names.rds"))

## Load the full Wave 6 WVS data:
dat0 <- readRDS(paste0(dataDir, fileName))

## Try to confirm that we're working with the correct data:
check <- all(dat0$V1 == 6)
if(!check)
    stop("This does not appear to be Wave 6 data. Are you sure you've downloaded the correct file?")

## Subset the data:
dat0 <- dat0[dat0$V2 %in% c(156, 276, 356, 643, 840), varNames]

## Convert the data to a basic data.frame:
dat0 <- as.data.frame(dat0)

## Write out the processed data:
saveRDS(dat0, paste0(dataDir, "wvs_data.rds"))
