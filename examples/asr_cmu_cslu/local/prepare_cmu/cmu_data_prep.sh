#! /bin/bash
## Copyright Johns Hopkins University
#   2019 Fei Wu

# Prepares cmu_kids. 
# Should be run from egs/cmu_cslu_kids


set -eu
stage=0

kaldi=../../speech_tools/kaldi
corpus=cmu_kids/kids

data=data/cmu
data_hires=data/cmu_hires
db=data/all_data.db
mfcc=false
hires_mfcc=false
mfcc_dir=mfcc/cmu

. ./utils/parse_options.sh
. ./path.sh
. ./cmd.sh

mkdir -p $data 

if [ $stage -le 0 ]; then
    ./local/backup_data_dir.sh $data
    
    for kid in $corpus/*; do 
    	if [ -d $kid ]; then
            # echo "Kid: $kid"
    		spkID=$(basename $kid)
    		sph="$kid/signal"
    	    if [ -d $sph ];then
                # echo "$sph"
                for utt in $sph/*; do
                    if [ ${utt: -4} == ".sph" ]; then
                        uttID=$(basename $utt)
                        uttID=${uttID%".sph"}
                        sentID=${uttID#$spkID}
                        sentID=${sentID:0:3}
    
                        # Find and clean sentence
                        sent=$(grep $sentID cmu_kids/tables/sentence.tbl | \
                            cut -f 3- | \
                            tr '[:lower:]' '[:upper:]' | \
                            tr -d '[:cntrl:]')
    
                        echo "$uttID $spkID" >> $data/utt2spk
                        echo "$uttID $kaldi/tools/sph2pipe_v2.5/sph2pipe -f wav -p -c 1 $utt|" >> $data/wav.scp
                        echo "$spkID f" >> $data/spk2gender
                        echo "$uttID $sent" >> $data/text
                    fi
                done
            fi
    	fi
    done
   ./local/clean_apostrophe.sh $data  
    utils/utt2spk_to_spk2utt.pl $data/utt2spk > $data/spk2utt
    utils/fix_data_dir.sh $data
fi

if [ $stage -le 1 ]; then
   if [ "$mfcc" == "true" ]; then
       mkdir -p $mfcc_dir
       steps/make_mfcc.sh \
           --nj 20 \
           --mfcc-config conf/mfcc.conf \
           --cmd "queue.pl" \
           $data $data/make_feat_log $mfcc_dir
       steps/compute_cmvn_stats.sh \
           $data $data/make_feat_log $mfcc_dir
   fi
fi

if [ $stage -le 2 ]; then
    if [ "$hires_mfcc" == "true" ]; then
        rm -rf $data_hires
        cp -r $data $data_hires
        steps/make_mfcc.sh \
           --nj 20 \
           --mfcc-config conf/mfcc_hires.conf \
           --cmd "queue.pl" \
           $data_hires $data_hires/make_feat_log $mfcc_dir
        steps/compute_cmvn_stats.sh \
            $data_hires $data_hires/make_feat_log $mfcc_dir
   fi
fi

if [ $stage -le 3 ]; then
    python3 ./local/db/data2db.py \
        --data_dir $data \
        --hires_dir $data_hires \
        --corpus cmu \
        --db_file $db \
        --schema local/db/schema.sql
fi
