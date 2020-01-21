#! /bin/bash 
set -euo

stage=0
data=data/cslu
data_hires=data/cslu_hires
db=data/all_data.db
mfcc=false
hires_mfcc=false
spon=false
mfcc_dir=mfcc/cslu

. ./utils/parse_options.sh
. ./path.sh
. ./cmd.sh

Looper() {
    echo "Looping through $1"

    for f in $1/*; do 
        if [ -d $f ]; then
            Looper $f $2
        else            
            if [ "$2" == "scripted" ]; then
                ./local/prepare_cslu/cslu_prepare_scripted.sh \
                    --audio $f \
                    --data $data 
            fi
            if [ "$2" == "spontaneous" ]; then
                local/prepare_cslu/cslu_prepare_spontaneous.sh \
                    --audio $f \
                    --data $data 
            fi
        fi
    done
}

mkdir -p $data
# Prepare scripted
if [ $stage -le 0 ]; then
    mkdir -p $data/scripted
    rm -f $data/scripted.log
    ./local/backup_data_dir.sh $data/scripted
    Looper "cslu/speech/scripted" "scripted"
    if [ -f $data/scripted.log ]; then 
        echo "Missing scripts for some utterances. See $data/scripted.log."
    fi
    ./utils/utt2spk_to_spk2utt.pl $data/scripted/utt2spk > $data/scripted/spk2
    ./utils/fix_data_dir.sh $data/scripted
fi

# Prepare spontaneous
if [ $stage -le 1 ]; then
    if [ "$spon" == "true" ]; then
        mkdir -p $data/spontaneous
        rm -f $data/spontaneous.log
        ./local/backup_data_dir.sh $data/spontaneous
        Looper cslu/speech/spontaneous spontaneous
        ./utils/utt2spk_to_spk2utt.pl $data/spontaneous
        ./utils/fix_data_dir.sh $data/spontaneous
        ./utils/combine_data.sh $data $data/scripted $data/spontaneous
    else
        mv $data/scripted/* $data/
        rm -rf $data/scripted
    fi

fi

# mfcc features
if [ $stage -le 2 ]; then
    if [ "$mfcc" == "true" ]; then
        mkdir -p $mfcc_dir
        steps/make_mfcc.sh \
            --mfcc-config conf/mfcc.conf \
            --nj 40 \
            --cmd "queue.pl" \
            $data $data/make_feat_log $mfcc_dir
        steps/compute_cmvn_stats.sh \
            $data $data/make_feat_log $mfcc_dir
    fi
fi

# mfcc features
if [ $stage -le 3 ]; then
    if [ "$hires_mfcc" == "true" ]; then
        rm -rf $data_hires
        cp -r $data $data_hires/
        steps/make_mfcc.sh \
            --mfcc-config conf/mfcc_hires.conf \
            --nj 40 \
            --cmd "queue.pl" \
            $data_hires $data_hires/make_feat_log $mfcc_dir
        steps/compute_cmvn_stats.sh \
            $data_hires $data_hires/make_feat_log $mfcc_dir
    fi
fi

if [ $stage -le 4 ]; then
    python3 ./local/db/data2db.py \
        --data_dir $data \
        --hires_dir $data_hires \
        --corpus cslu \
        --db_file $db \
        --schema local/db/schema.sql
fi
