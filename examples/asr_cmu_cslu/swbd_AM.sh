#!/bin/bash
# Copyright (c) Hang Lyu, Yiming Wang
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -e -o pipefail
set -e -o pipefail

stage=0
ngpus=1 # num GPUs for multiple GPUs training within a single node; should match those in $free_gpu
free_gpu=`free-gpu` # comma-separated available GPU ids, eg., "0" or "0,1"; automatically assigned if on CLSP grid

# E2E model related
affix=
train_set=train
valid_set=dev
test_set="cmu_test cslu_test"
checkpoint=checkpoint_best.pt

# LM related
lm_affix=
lm_checkpoint=checkpoint_best.pt
lm_shallow_fusion=true # no LM fusion if false
sentencepiece_vocabsize=5000
sentencepiece_type=unigram

lm_train_set=train_960  # LM trained on librispeech text
lm_log_dir=exp/lm_log


# data related
dumpdir=data/dump   # directory to dump full features
# if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -L $dumpdir ]; then
#     tmp_link=/export/b0{3,4,5,6}/${USER}/espresso-data/dump/cmu_cslu-$(date +'%m_%d_%H_%M')
#     ln -s $tmp_link $dumpdir
# fi

data=data
corpus_cmu=
corpus_cslu=

train_rate=0.7
dev_rate=0.15
test_rate=0.15
all_data_db=data/all_data.db
split_by='spk'

kaldi_scoring=true

# feature configuration
do_delta=false


. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh

lm_pretrained=exp/lm_lstm${lm_affix:+_${lm_affix}}
lmdir=exp/lm_tuned
dir=exp/lstm_swbd
mkdir -p $dir

dict=data/lang/train_960_unigram5000_units.txt

train_feat=${dumpdir}/${train_set}/delta${do_delta}/feats.scp
train_token_text=data/$train_set/token_text
valid_feat=${dumpdir}/${valid_set}/delta${do_delta}/feats.scp
valid_token_text=data/$valid_set/token_text

if [ $stage -le 8 ]; then
  echo "Stage 8: Model Training"
  valid_subset=valid
  opts=""
  [ -f local/wer_output_filter ] && opts="$opts --wer-output-filter local/wer_output_filter"
  mkdir -p $dir/logs
  log_file=$dir/logs/train.log
  [ -f $dir/checkpoint_last.pt ] && log_file="-a $log_file"
  CUDA_VISIBLE_DEVICES=$free_gpu speech_train.py --seed 1 \
    --log-interval 1500 --log-format simple --print-training-sample-interval 2000 \
    --num-workers 0 --max-tokens 26000 --max-sentences 48 \
    --valid-subset $valid_subset --max-sentences-valid 64 \
    --distributed-world-size $ngpus --distributed-rank 0 --distributed-port 100 --ddp-backend no_c10d \
    --max-epoch 35 --optimizer adam --lr 0.001 --weight-decay 0.0 --clip-norm 2.0 \
    --lr-scheduler reduce_lr_on_plateau_v2 --lr-shrink 0.5 --min-lr 1e-5 --start-reduce-lr-epoch 10 \
    --save-dir $dir --restore-file checkpoint_last.pt --save-interval-updates 1500 \
    --keep-interval-updates 3 --keep-last-epochs 5 --validate-interval 1 --best-checkpoint-metric wer \
    --arch speech_conv_lstm_swbd --criterion label_smoothed_cross_entropy_with_wer \
    --label-smoothing 0.1 --smoothing-type uniform \
    --scheduled-sampling-probs 0.9,0.8,0.7,0.6 --start-scheduled-sampling-epoch 6 \
    --train-feat-files $train_feat --train-text-files $train_token_text \
    --valid-feat-files $valid_feat --valid-text-files $valid_token_text \
    --dict $dict --remove-bpe sentencepiece \
    --max-source-positions 9999 --max-target-positions 999 $opts 2>&1 | tee $log_file
fi

if [ $stage -le 9 ]; then
  echo "Stage 9: Decoding"
  [ ! -d $KALDI_ROOT ] && echo "Expected $KALDI_ROOT to exist" && exit 1;
  opts=""
  path=$dir/$checkpoint
  decode_affix=
  if $lm_shallow_fusion; then
    path="$path:$lmdir/$lm_checkpoint"
    opts="$opts --lm-weight 0.25 --coverage-weight 0.0"
    decode_affix=shallow_fusion
  fi
  [ -f local/wer_output_filter ] && opts="$opts --wer-output-filter local/wer_output_filter"
  for dataset in $test_set; do
    decode_dir=$dir/decode_${dataset}${decode_affix:+_${decode_affix}}
    # only score train_dev with built-in scorer
    text_opt= && [ "$dataset" == "train_dev" ] && text_opt="--test-text-files data/$dataset/token_text"
    CUDA_VISIBLE_DEVICES=$(echo $free_gpu | sed 's/,/ /g' | awk '{print $1}') speech_recognize.py \
      --max-tokens 24000 --max-sentences 48 --num-shards 1 --shard-id 0 \
      --test-feat-files ${dumpdir}/$dataset/delta${do_delta}/feats.scp $text_opt \
      --dict $dict --remove-bpe sentencepiece --non-lang-syms $nlsyms \
      --max-source-positions 9999 --max-target-positions 999 \
      --path $path --beam 35 --max-len-a 0.1 --max-len-b 0 --lenpen 1.0 \
      --results-path $decode_dir $opts \
      2>&1 | tee $dir/logs/decode_$dataset${decode_affix:+_${decode_affix}}.log

    echo "Scoring with kaldi..."
    local/score.sh data/$dataset $decode_dir
    if [ "$dataset" == "train_dev" ]; then
      echo -n "tran_dev: " && cat $decode_dir/scoring/wer | grep WER
    elif [ "$dataset" == "eval2000" ] || [ "$dataset" == "rt03" ]; then
      echo -n "$dataset: " && grep Sum $decode_dir/scoring/$dataset.ctm.filt.sys | \
        awk '{print "WER="$11"%, Sub="$8"%, Ins="$10"%, Del="$9"%"}' | tee $decode_dir/wer
      echo -n "swbd subset: " && grep Sum $decode_dir/scoring/$dataset.ctm.swbd.filt.sys | \
        awk '{print "WER="$11"%, Sub="$8"%, Ins="$10"%, Del="$9"%"}' | tee $decode_dir/wer_swbd
      subset=callhm && [ "$dataset" == "rt03" ] && subset=fsh
      echo -n "$subset subset: " && grep Sum $decode_dir/scoring/$dataset.ctm.$subset.filt.sys | \
        awk '{print "WER="$11"%, Sub="$8"%, Ins="$10"%, Del="$9"%"}' | tee $decode_dir/wer_$subset
      echo "WERs saved in $decode_dir/wer*"
    fi
  done
fi
