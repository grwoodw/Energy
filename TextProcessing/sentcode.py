#!/user/kh3191/.conda/envs/nlp/bin/python

"""
    Function           : This code prepares the sentiment scores
                        and counts the total number of words after cleaning for each article
"""

import numpy as np
import pandas as pd
import re
import textmining

from utils import mark_neg, get_clean, get_total

from pandarallel import pandarallel
pandarallel.initialize(progress_bar=False)
from tqdm import tqdm

import os

######################################################## 
# 
# File Paths 
# 
########################################################

import argparse
from argparse import RawTextHelpFormatter
def parse_option():
    parser = argparse.ArgumentParser(formatter_class=RawTextHelpFormatter)
    parser.add_argument('--sentDicPath', type=str, default='2014.txt')
    parser.add_argument('--inputPath', type=str, 
           default='/shared/share_mamaysky-glasserman/energy_drivers/2023/DataProcessing/oil_info')
    parser.add_argument('--outputPathSent', type=str, 
           default='/shared/share_mamaysky-glasserman/energy_drivers/2023/DataProcessing/article_measure/sentiment')
    parser.add_argument('--outputPathTotal', type=str, 
           default='/shared/share_mamaysky-glasserman/energy_drivers/2023/DataProcessing/article_measure/total')
    opt = parser.parse_args()
    return opt

opt = parse_option()
print(opt)


def get_Neg(sample):
        words = [word for word in sample if word in Neg]
        return ' '.join(words)

def get_Pos(sample):
    words = [word for word in sample if word in Pos]
    return ' '.join(words)

# def get_uncertain(sample):
#     sample = sample.split(' ')
#     words = [word for word in sample if word in Uncertain]
#     return ' '.join(words)


def write_sent_total(file):
    YYYYMM = file[-15:-9]
    Temp = pd.read_csv(f"{opt.inputPath}/{file}",sep=',',encoding = "ISO-8859-1")
    Temp['augbod'] = Temp['augbod'].str.lower()
    Temp['body_stem'] = Temp['augbod'].parallel_apply(get_clean)
    Temp['body_negation'] = Temp['augbod'].parallel_apply(mark_neg)
    Temp['body_Neg'] = Temp['body_negation'].parallel_apply(get_Neg)
    Temp['body_Pos'] = Temp['body_negation'].parallel_apply(get_Pos)
    Temp['body_total'] = Temp['body_stem'].parallel_apply(get_total)

    ngram_Neg = textmining.TermDocumentMatrix()
    for f in Temp['body_Neg']:
        ngram_Neg.add_doc(f)

    ngram_Pos = textmining.TermDocumentMatrix()
    for f in Temp['body_Pos']:
        ngram_Pos.add_doc(f)

    Final = []
    Id = list(Temp['Id'])
    for i in range(len(Id)):
        temp_pos = []
        temp_neg = []
        pos = 0
        neg = 0
        for words,num in ngram_Pos.sparse[i].items():
            pos += num
        for words,num in ngram_Neg.sparse[i].items():
            neg += num
        Final.append((Id[i],(pos-neg)/Temp['body_total'][i]))
    df_sent = pd.DataFrame(Final,columns = ['Id','sent'])   
    df_sent.to_csv(f"{opt.outputPathSent}/{YYYYMM}_sent.csv",index=False)

    df_total = Temp[['Id','body_total']].rename(columns={'body_total': 'total'})
    df_total.to_csv(f"{opt.outputPathTotal}/{YYYYMM}_total.csv",index=False)

        
if __name__ == "__main__":

    with open(opt.sentDicPath, 'r') as f:
        content = f.readlines()
        Line = []
        for l in content:
            line = l.strip()
            line = re.sub('[^A-Za-z]', ' ', line)
            line_list = line.strip().split('\n')
            Line.extend(line_list)

    neg_index = Line.index('NEGATIVE')
    pos_index = Line.index('POSITIVE')
    uncertain_index = Line.index('UNCERTAINTY')
    #LITIGIOUS_index = Line.index('LITIGIOUS')

    neg = Line[neg_index+1:pos_index]
    pos = Line[pos_index+1:uncertain_index]
    #uncertain = Line[uncertain_index+1:LITIGIOUS_index]

    Neg = [l.lower() for l in neg]
    Pos = [l.lower() for l in pos]
    #Uncertain = [l.lower() for l in uncertain]

    # !!crucial for efficiency!!
    Neg = set(Neg)
    Pos = set(Pos)

    for file in tqdm(os.listdir(opt.inputPath)):
        write_sent_total(file)

