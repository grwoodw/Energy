import pandas as pd
import os, re
from datetime import datetime, timedelta, date
import matplotlib.pyplot as plt
import seaborn as sns

__text_dir__ = '/shared/share_mamaysky-glasserman/energy_drivers/2020-11-16'
__out_dir__ = '/user/hm2646/code/Energy/Analysis/results'

############################## Read in processed data ##############################

def read_info():

    ## list all files
    info_dir = __text_dir__+'/DataProcessing/info/'
    fnames = sorted(os.listdir(info_dir))

    ## read all files
    dfs = []

    for nm in fnames:
        fname = info_dir+nm
        print('Reading "',fname,'"',sep='')

        dfs.append(pd.read_csv(fname,index_col='Id'))

    return pd.concat(dfs)


def read_processed(saveout=True):

    ## 12/16/2020: Hongyu says this is the data we're using for the paper
    fname = __text_dir__ + '/data/transformed_data_prices_v14.dta'
    print('Reading in "',fname,'"',sep='')
    procd = pd.read_stata(fname)

    ## mapping from topic numbers to names
    top_short = {'1':'Co','2':'Gom','3':'Env','4':'Epg','5':'Bbl','6':'Rpc','7':'Ep'}
    top_long = {'1':'Company (Co)','2':'Global Oil Markets (Gom)','3':'Environment (Env)',
                '4':'Energy/Power Generation (Epg)','5':'Crude Oil Physical (Bbl)',
                '6':'Refining & Petrochemicals (Rpc)','7':'Exploration & Production (Ep)'}

    ## save?
    if saveout:

################################################## also take , 

        
        ft1 = ['ftopic'+str(el) for el in [1,2,3,4,5,6,7]]
        st1 = ['stopic'+str(el) for el in [1,2,3,4,5,6,7]]
        subd = procd[['date_thurs','Artcount','Entropy',*ft1,*st1,
                      'artcount_4wk','entropy_4wk',
                      *[el+'_4wk' for el in ft1],
                      *[el+'_4wk' for el in st1],
                     'PCAsent','PCAfreq','PCAall']]
        fname = __out_dir__ + '/text-data-' + str(date.today()) + '.csv'
        print('Saving to',fname)
        subd.to_csv(fname)
    
    ## return the data and the topic map
    return {'data':procd,'top_short':top_short,'top_long':top_long}


def summary(serd):
    
    ## look at the correlation matrix of the 7 frequency and topical sentiment series
    f_nms = ['ftopic{}_4wk'.format(el) for el in serd['top_short'].keys()]
    s_nms = ['stopic{}_4wk'.format(el) for el in serd['top_short'].keys()]

    cm = serd['data'][[*f_nms,*s_nms]].corr()
    plt.figure(figsize=(12,12))
    sns.heatmap(cm,annot=True)  ## show numerical values


############################## display series and articles ##############################

## For a given date and topic number, show recent articles that might indicate
## what's going on.
def show_articles(txtd,date_str,top_num,disp_name):

    lookback_days = 28
    topic_thresh = 0.8
    num_articles = 5
    min_length = 100
    min_entropy = 2
    
    date2 = datetime.strptime(date_str,'%Y-%m-%d')
    date1 = date2 - timedelta(days=lookback_days)
                
    ## find all text articles in this topic within the lookback window
    loctxt = txtd[(txtd.TimeStamp_NY >= str(date1)) &
                  (txtd.TimeStamp_NY <= str(date2)) &
                  (txtd.entropy >= min_entropy) &
                  (txtd.total >= min_length) &
                  (txtd['Topic{}'.format(top_num)] > topic_thresh)].sort_values('sentiment')

    ## show output of article headlines
    rows = []

    rows.append({'Sent':None,'Ent':None,'Date':None,
                 'Headline':'{} from {} to {}'.format(disp_name,str(date1)[:10],str(date2)[:10])})

    for jj in range(min(num_articles,loctxt.shape[0])):
        rows.append({'Sent':'{:.3f}'.format(loctxt.iloc[jj]['sentiment']),
                     'Ent':'{:.3f}'.format(loctxt.iloc[jj]['entropy']),
                     'Date':'{}'.format(loctxt.iloc[jj]['TimeStamp_NY'][:10]),
                     'Headline':'{}'.format(loctxt.iloc[jj]['headline'])})

    ## return data frame
    thed = pd.DataFrame(rows)
    print(thed)
    return thed
        

def plot_text_stats(serd):

    labels = {'artcount_4wk':'Article Counts',
              'entropy_4wk':'Entropy',              
              'PCAsent':'First PC of Normalized Topical Sentiment',
              'PCAfreq':'First PC of Normalized Topical Frequency',
              'PCAall':'First PC of All Normalized Text Variables'}
    
    plt.figure(figsize=(10,9))
    nrow = 3
    ncol = 2

    for ii,ser in enumerate(labels.keys()):

        ax = plt.subplot(nrow,ncol,ii+1)
        ax.plot(serd['data'].date_wed,serd['data'][ser],color='blue')
        ax.set_title(labels[ser])

    plt.suptitle('Panel C: Article Counts, Entropy, and Principal Components',fontsize=18)
    plt.tight_layout()

    fname = __out_dir__+'/Figure-2-Panel-C-'+date.today().strftime('%Y-%m-%d')+'.png'
    print('Saving figure to',fname)
    plt.savefig(fname)


def show_outliers(serd,txtd):
    ''' Show a specific set of dates and outliers. '''

    ## these are manually located using find_outliers().
    event_dates = {'1':('2000-09-20','UK fuel protests'),
                   '2':('2002-04-24','Failed Venezuelan coup'),
                   '3':('2015-10-14','Volkswagen emissions scandal'),
                   '4':('2002-02-13','Post-bankruptcy Enron hearings'),
                   '5':('2005-09-21','Hurricane Katrina'),
                   '6':None,
                   '7':('2010-06-02','BP oil spill aftermath')}

    ## dimensions of the picture
    nrow = 2
    ncol = 4

    ## plot the different panels
    for ser in ('ftopic','stopic'):
        
        print(ser)

        ## to store the table
        rows = []

        ## plotting
        plt.figure(ser,figsize=(14,8))
        
        for top_num in serd['top_short'].keys():

            ## get the column name for the {series,topic} pair, e.g., ftopic4_wk
            top_ser = '{}{}_4wk'.format(ser,top_num)
            
            ax = plt.subplot(nrow,ncol,int(top_num))
            ax.plot(serd['data'].date_wed,
                    serd['data'][top_ser],color='blue')
            ax.set_title(serd['top_long'][top_num])

            ## add event points
            if event_dates[top_num] != None:
                event_date = event_dates[top_num][0]
                ax.plot(datetime.strptime(event_date,'%Y-%m-%d'),
                        serd['data'].loc[serd['data'].date_wed == event_date,
                                         top_ser],
                        marker='*',color='red',markersize=16)

                ## get the rows of the headline tables
                rows.append(show_articles(txtd,event_date,top_num,
                                          '{}: {}'.format(serd['top_short'][top_num],
                                                    event_dates[top_num][1])))
                
        ## more plot formatting
        plt.suptitle('Panel A: Topical Frequency' if ser == 'ftopic'
                     else 'Panel B: Topical Sentiment', fontsize=18)
        plt.tight_layout()

        ## save the pics and show the tables
        if ser == 'stopic':

            ## tables
            thed = pd.concat(rows)
            fname = __out_dir__+'/sample-sentences-'+date.today().strftime('%Y-%m-%d')+'.csv'
            print('Saving to',fname)
            thed.to_csv(fname)

            fname = __out_dir__+'/Figure-2-Panel-B-'+date.today().strftime('%Y-%m-%d')+'.png'
            
        else:

            fname = __out_dir__+'/Figure-2-Panel-A-'+date.today().strftime('%Y-%m-%d')+'.png'

        ## pics
        print('Saving figure to',fname)
        plt.savefig(fname)
            
            
############################## find outlier dates ##############################

def find_outliers(serd,txtd):
    ''' Find outlier dates and articles. '''
    
    ## find the sentiment 4wk columns
    ## ntop -- number of top outliers
    ## lookback -- number of days to look back
    def series_outliers(col_str,label,sort_ascending):

        ntop = 2    ## number of top events to examine
        n_diff = 4  ## number of weeks over which to difference for identifying outliers
        
        ## find the columns to search through
        topics = serd['top_short'].keys()

        ## go through all the columns
        for top_num in topics:

            ## get the data corresponding to this series
            top_ser = '{}{}_4wk'.format(col_str,top_num)
            top_name = '{} {}'.format(label,serd['top_short'][top_num])
            used = serd['data'][['date_wed',top_ser]].copy()
            used['dSer'] = used[top_ser].diff(n_diff)
            used = used.sort_values('dSer',ascending=sort_ascending)

            ## keep output string
            print('***',top_name,'***',end='\n\n')
            
            ## go through the more extreme months in each
            for ii in range(ntop):

                ## these are the {news-series,date} pairs for outlier events
                show_articles(txtd,str(used.iloc[ii]['date_wed'])[:10],top_num,top_name)
                
                ## the output string
                print()

    series_outliers('stopic','Sent',sort_ascending=True)
