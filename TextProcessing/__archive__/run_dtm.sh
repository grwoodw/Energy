#!/bin/bash

DATA1='/work/hw2676/Energy/oil_RTRS'
FS='/user/hw2676/code/Energy/DataProcessing/article_measure/dtm'

 
cd $DATA1
for f in *.csv
do
	# Strip path to article file.
	X=${f}
	sge_run --grid_mem=32G --grid_ncpus=1 --grid_submit=batch --grid_quiet "${FS}/dtm.py ${f}"
done	
