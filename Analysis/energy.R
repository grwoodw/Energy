require(magrittr)
require(corrplot)

calc <- function(object) UseMethod('calc')
savedata <- function(object) UseMethod('savedata')
calc_rp <- function(object,...) UseMethod('calc_rp')
.energy_res_dir <- '~/GoogleDrive/work/code/energy'

DriverEnergy <- function() {

  ## get the data
  ed <- EnergyData()  ## ***
  savedata(ed)
  plot(ed)

  ed <- loaddata.EnergyData()  ## ***
  ed <- calc(ed)     ## ***  get some derived data from the raw data
  calc_rp(ed,0)      ## ***  The full-sample SDF risk premia
  calc_rp(ed,252*3)  ## ***  The rolling SDF risk premia
  calc_rp(ed,-1)     ## ***  The growing window SDF

  ## the returns vs vol analysis
  plotPercAndVols(ed$data$brent,'Brent')
  plotPercAndVols(ed$data$brent,'Brent',end.date='2007-12-31')
  plotPercAndVols(ed$data$brent,'Brent',,start.date='2008-01-01')
  plotPercAndVols(ed$data$wti_fut_tr,'WTI Futures TR')
  plotPercAndVols(ed$data$wti_fut_tr,'WTI Futures TR',end.date='2007-12-31')
  plotPercAndVols(ed$data$wti_fut_tr,'WTI Futures TR',start.date='2008-01-01')
  plotPercAndVols(ed$data$sptr,WinLen=21,'SPTR')
  plotPercAndVols(ed$data$sptr,'SPTR')
  plotPercAndVols(ed$data$sptr,'SPTR',end.date='2007-12-31')
  plotPercAndVols(ed$data$sptr,'SPTR',start.date='2008-01-01')

  ## futures returns
  plotFuturesRets(ed$data)
}

############################## get the data ##############################

#' Get futures data.
EnergyData <- function(start.date='1980-01-01') {

  ## these are the first three futures, and get rolled by BBG automatically
  futs <- c('cl1','cl2','cl3')
  thed <- bdh1(c(paste(futs,'comdty'),
                 'USCRWTIC Index',   ## WTI
                 'CSMFWTTR Index',   ## WTI future return
                 'EUCRBRDT index',   ## brent
                 'NDWUENR index',    ## energy stocks
                 'sptr index',
                 'm1wdu index',
                 'sbhymi index',
                 'luattruu index',
                 'gb06 govt'
                 ),
               'px_last', start.date=start.date) %>%
    'colnames<-'(c(futs,'wti','wti_fut_tr','brent','energy','sptr','wxus','hyus','ustreas','us6mo'))

  structure(list(data = thed,
                 start.date=start.date),
            class='EnergyData')
}

savedata.EnergyData <- function(object) {
  saveRDS(object,file=paste0(.energy_res_dir,'/energy-data-',Sys.Date(),'.rds'))
}

loaddata.EnergyData <- function() {
  fname <- list.files(.energy_res_dir,full.names=TRUE) %>% grep('[.]rds',.,value=TRUE) %>%
    sort %>% tail(1)
  cat('Loading in',dQuote(fname),'\n')
  readRDS(fname)
}

#' Some derived data from the raw price data.
calc.EnergyData <- function(object) {

  thed <- object$data
  object$dpy <- 252

  stopifnot(class(index(thed))=='Date',
            mean(diff(index(thed)))<1.6)  ## make sure daily data

  ## convert the t-bill series to a total return
  ## lag(-1) to apply yesterday's rate to today's return
  tr <- cumprod(1+lag(na.locf(thed$'us6mo'),-1)/(100*object$dpy))
  first_idx <- which(index(thed)==index(na.omit(thed$'us6mo'))[[1]])
  thed$'us6mo_tr' <- NA
  thed$'us6mo_tr'[index(tr)] <- tr
  thed$'us6mo_tr'[first_idx] <- 1

  ## renormalize the TR indexes
  first_idx <- index(na.omit(thed$wti_fut_tr))[[1]]
  for (fld in c('wti_fut_tr','sptr','ustreas','us6mo_tr'))
    thed[,fld] <- thed[,fld] / thed[first_idx,fld][[1]] * thed[first_idx,'wti'][[1]]

  object$data <- thed

  object
}

print.EnergyData <- function(object) str(object,2)

plot.EnergyData <- function(object) {

  ## setup for plots
  cols <- ltys <- 1:ncol(object$data)
  lwds <- 1.5

  ## plotting levels
  other_names <- 'us6mo'
  tr_names <- setdiff(colnames(object$data),other_names)

  dev.new(title=win_t<-'Prices')
  par(mfrow=c(2,1),mar=c(3,3,1,1),mgp=c(2,1,0))

  ## the total returns
  plot(log(object$data[,tr_names]),plot.type='single',col=cols,lty=ltys,lwd=lwds,ylab='Log prices',xlab='')
  legend('topleft',tr_names,col=cols,lty=ltys,lwd=lwds,bty='n',nc=2)

  ## the other series
  plot(object$data[,other_names])
  legend('topleft',other_names,col=cols,lty=ltys,lwd=lwds,bty='n',nc=2)

  1
}


############################## the SDF analysis ##############################

#' @param train_win How many days to use to calc the SDF.  If 0, then use the
#' full-sample SDF.  If negative, then use increasing rolling windows.
calc_rp.EnergyData <- function(object,train_win=0,saveout=TRUE) {

  ## set up parameters
  if (train_win>0)
    sdf_desc <- sprintf('%i-day',train_win)
  else if (train_win<0) {
    sdf_desc <- 'growing-window'
    train_win <- nrow(object$data)
  }
  else
    sdf_desc <- 'full-sample'
  cov_win <- 252                                    ## window in which to estimate the covariance matrix for SDF
  min_for_train <- 252*3
  stopifnot(train_win <= 0 || train_win > cov_win)  ## if train_win > 0, must be longer than cov_win

  ## get the return series of interest
  sec_names <- c('wti_fut_tr','sptr','ustreas','us6mo_tr','energy')
  rets <- diff(object$data[,sec_names],1,arithmetic=FALSE)
  rets <- na.omit(rets)  ## drop NAs

  cat('\nThe WTI_FUT_TR (from CS) data starts in 1998, but is monthly in the first year.',
      'It becomes daily starting in 1999, but then we need the first year of the data to',
      'estimate the covariance matrix to extract the SDF.  So the first data point we get',
      'even for the full-sample SDF is in January 2000.\n\n', sep='\n')

  ## set up figure
  dev.new(title=win_t<-'Returns')
  plot(rets,main=win_t)
  NN <- nrow(rets)

  .calc_sdf <- function(rets_in,verbose=TRUE) {
    ## calculate the SDF in the linear span of the securities
    RR <- t(rets_in)  ## this is a N x T matrix of returns
    cc <- solve(1/NN * RR %*% t(RR)) %*%  matrix(1,nrow(RR),1)

    ## show the loadings of the SDF on the series?
    if (verbose)
      cat(sprintf('%12s=%5.3f',rownames(cc),cc),'\n')

    mm <- zoo(as.numeric(t(cc) %*% RR),index(rets_in))

    ## check the Euler equations E[mR]=1 hold
    ee <- sapply(colnames(rets_in), function(nm) mm %*% rets_in[,nm] / NN)
    stopifnot(all(abs(ee-1)<1e-8))

    ## return the SDF
    mm
  }

  ## get rolling estimates of risk premia
  .get_E_ret <- function(thed_in,sec_in) {
    R_e <- thed_in[,sec_in] - thed_in[,'us6mo_tr']
    NN <- nrow(thed_in)  ## take out the bias adjustment in cov()
    c(E_cov = (NN-1)/NN*-cov(R_e,thed_in[,'mm']) / mean(thed_in[,'mm']) * object$dpy,
      avg_R_e = mean(R_e) * object$dpy)  ## just the mean return in this window
  }

  ## get the full-sample SDF (needed even with rolling SDF for diagnostic at bottom of code)
  mm <- .calc_sdf(rets)

  ## calc SDF over rolling windows and get the sample covariance at end of the window
  tt <- 0
  E_rets <-
    rollapplyr(cbind(rets,mm), max(cov_win,train_win),
               ## ensure minimum size window in rolling calcs
               partial=ifelse(train_win>0,min_for_train,FALSE),
               by.column=FALSE, function(used) {

                 ## check if show output
                 tt <<- tt+1
                 if (tt %% 500 == 0) {
                   verb <- TRUE
                   cat(tt,': window size=',nrow(used),'\n',sep='')
                 }
                 else
                   verb <- FALSE

                 ## this means rolling windows
                 if (train_win > 0) {
                   ## here recalc the SDF in the rolling training window
                   used[,'mm'] <- .calc_sdf(used[,setdiff(colnames(used),'mm')],verb)
                   nr <- nrow(used)
                   used <- used[(nr-cov_win+1):nr,]
                 }

                 ## get a 2 x N matrix of expected and avg excess returns for the securities
                 res <- sapply(sec_names, function(sec) .get_E_ret(used,sec))

                 ## combine both rows into a single row of expected and avg excess returns
                 c(res['E_cov',],res['avg_R_e',]) %>%
                   'names<-'(c(paste0('E_',sec_names),paste0('r_',sec_names)))
               })

  cat('\n')

  ## plot the rolling risk premia, as well as the average within period returns
  use_secs <- colnames(E_rets) %>% {.[!grepl('us6mo_tr',.)]}

  chart_title <- sprintf('Rolling annualized risk-premia with %i-day cov and %s SDF',
                         cov_win, sdf_desc)
  dev.new(width=9,height=6)

  plotz(E_rets[,use_secs], nc=2, addfunc = function(x,y,lab) {
    abline(h=0,lty=2,col='grey76')
    legend('topleft',sprintf('Mean = %.3f',mean(y)),bty='n')
  }, col = 'steelblue3',lwd=2,main = chart_title)

  ## correlations
  dev.new(title=win_t<-'Correlations')
  corrplot.mixed(cor(E_rets[,use_secs]),upper='square',title=win_t,tl.cex=0.85,mar=c(0,0,1,0))

  ## calculate the full-sample M implied
  sapply(sec_names, function(sec) .get_E_ret(cbind(rets,mm),sec)) %>% print

  ## save output of analysis
  if (saveout) {
    fname <- paste0('~/GoogleDrive/work/code/energy/SDF-',sdf_desc,'-',Sys.Date(),'.csv')
    cat('Writing output to:',fname,'\n')
    write.csv(as.data.frame(E_rets),file=fname)
  }

  invisible(E_rets)
}

############################## rets and vol analysis ##############################

plotPercAndVols <- function(ser_in,label,WinLen=84,
                            start.date=NULL,end.date=Sys.Date()) {

  .locplot <- function(laggedVol=FALSE) {

    ## get % changes and vols
    rets <- 100*diff(ser,lag=WinLen,arithmetic=FALSE)-100
    vols <- rollapplyr(ser,WinLen+1,
                       function(lser) sqrt(252)*100*sd(lser[-1]/lser[-length(lser)],na.rm=TRUE))

    ## display stuff
    if (laggedVol) {
      volstr <- sprintf('lagged volatility (annualized, %.0f days)',WinLen)
      prcvol <- cbind(rets = rets,vols = lag(vols,-WinLen))
    }
    else {
      volstr <- sprintf('volatility (annualized, %.0f days)',WinLen)
      prcvol <- cbind(rets = rets,vols = vols)
    }

    sernames <- paste0(c('% chg','vols'),' (',WinLen,' days)')
    ylab_str <- sprintf('%% changes (%.0f days)',WinLen)

    ## plot the time series
    plot(prcvol[,1],col=cols[1],lty=ltys[1],lwd=lwds[1],ylab=ylab_str,xlab='')
    par(new=TRUE)
    plot(prcvol[,2],col=cols[2],lty=ltys[2],lwd=lwds[2], yaxt='n', ylab='', xlab='')
    axis(4, at=round(seq(min(prcvol[,2],na.rm=T),max(prcvol[,2],na.rm=T),l=6),digits=1), labels=)
    mtext(volstr, side=4, line=3, cex.lab=1)

    legend('topleft',c(sernames,sprintf('Cor = %.3f',cor(prcvol,use='comp')[[1,2]])),
           col=cols,lty=c(ltys,NA),lwd=lwds,bty='n')

    ## plot the scatter plots
    plot(prcvol$vols,prcvol$rets,ylab=ylab_str,xlab=volstr,pch=20,col='steelblue3')
    regr <- lm(rets ~ vols, data=prcvol)
    sumregr <- summary(regr)
    abline(regr,lty=2,col='red')
    legend('topright',c(sprintf('b=%.3f (t=%.2f)',
                                coefficients(regr)[[2]],
                                coefficients(sumregr)[['vols','t value']]),
                        sprintf('R2=%.3f',sumregr$adj.r.squared)), bty='n')
  }

  ## restrict to desired window, and drop all initial NA's
  ser <- window(ser_in,start=start.date,end=end.date)
  first_idx <- min(which(!is.na(ser))) %>% {max(.-1,1)}
  ser <- ser[first_idx:length(ser)]

  ## plotting vols
  lwds <- 1.5
  cols <- c('steelblue3','red')
  ltys <- c(1,4)

  dev.new(title=win_t<-paste(label,'changes and volatilities',
                             format(index(ser)[[1]],'%Y-%m'),'to',format(tail(index(ser),1),'%Y-%m')),
          width=10,height=7)
  par(mfrow=c(2,2),mar=c(3,4,1,6),mgp=c(2,1,0),oma=c(0.25,0,3,0))

  .locplot(laggedVol=FALSE)
  .locplot(laggedVol=TRUE)

  mtext(text=win_t, outer=TRUE, cex=1.25)
  save_window(win_t)

  1
}


############################## futures rets and basis ##############################

plotFuturesRets <- function(ser,fwdFillLim=3) {

  ## calculate the derived series
  ser <- ser[,setdiff(colnames(ser),c('brent','sptr'))]
  ser <- na.locf(ser,maxgap=fwdFillLim)  ## fwd fill some NAs

  crv3s1s <- (ser$cl3/ser$cl1)^6 - 1

  ## plots
  cols <- 1:4
  ltys <- 1:4

  dev.new(title=win_t<-'Oil basis and returns',width=7,height=8)
  par(mfrow=c(3,2), mar=c(3,3,3,1), mgp=c(2,1,0))

  ## plot regression
  .runreg <- function(useser,label,Nlag=21) {

    retser <- diff(useser,Nlag,arithmetic=FALSE)*100 - 100
    usecrv <- lag(crv3s1s,-Nlag)

    plot(usecrv,retser,main='%Changes[t -> t+1] = a + b * Basis[t] * eps',
         ylab='%Changes', xlab='Basis')
    regr <- lm(rets ~ crv, data=cbind(rets=retser,crv=usecrv))
    sumregr <- summary(regr) %>% print

    abline(regr,lty=2,col='red')
    legend('bottomright',c(sprintf('b = %.3f (t=%.2f)',
                                   coefficients(regr)[[2]],
                                   coefficients(sumregr)[['crv','t value']]),
                           sprintf('R2 = %.4f',sumregr$adj.r.squared)),
           bty='n')
    legend('topright',label,bty='n',text.col='blue',cex=1.5)

  }

  ## the futures and spot prices
  plot(ser, plot.type='single', col=cols, lty=ltys, ylab='', xlab='',
       main='WTI prices and futures')
  legend('topleft',names(ser),col=cols,lty=ltys,bty='n')

  plot(crv3s1s, main='Basis = [F(3)/F(1)]^6 - 1', ylab='', xlab='')
  abline(h=0,lty=2,col='grey67')

  .runreg(ser$wti_fut_tr,'Futures % rets (daily)',1)
  .runreg(ser$wti,'Spot % chgs (daily)',1)

  .runreg(ser$wti_fut_tr,'Futures % rets (monthly)',21)
  .runreg(ser$wti,'Spot % chgs (monthly)',21)

  save_window(win_t)

  invisible(ser)

}
