#!/bin/bash
# Copyright (c) Yiming Wang
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

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
dir=exp/lstm_wsj
mkdir -p $dir

dict=data/lang/train_960_unigram5000_units.txt

train_feat=${dumpdir}/${train_set}/delta${do_delta}/feats.scp
train_token_text=data/$train_set/token_text
valid_feat=${dumpdir}/${valid_set}/delta${do_delta}/feats.scp
valid_token_text=data/$valid_set/token_text
if [ ${stage} -le 8 ]; then
  echo "Stage 8: Model Training"
  opts=""
  valid_subset=valid
  mkdir -p $dir/logs
  log_file=$dir/logs/train.log
  [ -f $dir/checkpoint_last.pt ] && log_file="-a $log_file"
  CUDA_VISIBLE_DEVICES=$free_gpu speech_train.py --seed 1 \
      --curriculum 2 \
      --log-interval 400 \
      --log-format simple \
      --print-training-sample-interval 1000 \
      --num-workers 0 \
      --max-tokens 24000 \
      --max-sentences 32 \
      --valid-subset $valid_subset \
      --max-sentences-valid 64 \
      --distributed-world-size $ngpus \
      --distributed-port 100 \
      --ddp-backend no_c10d \
      --max-epoch 35 \
      --optimizer adam \
      --lr 0.001 \
      --weight-decay 0.0 \
      --lr-scheduler reduce_lr_on_plateau_v2 \
      --lr-shrink 0.5 \
      --min-lr 1e-5 \
      --start-reduce-lr-epoch 11 \
      --save-dir $dir \
      --restore-file checkpoint_last.pt \
      --save-interval-updates 400 \
      --keep-interval-updates 5 \
      --keep-last-epochs 5 \
      --validate-interval 1 \
      --best-checkpoint-metric wer \
      --arch speech_conv_lstm_wsj \
      --criterion label_smoothed_cross_entropy_with_wer \
      --label-smoothing 0.05 \
      --smoothing-type temporal \
      --scheduled-sampling-probs 0.5 \
      --start-scheduled-sampling-epoch 6 \
      --train-feat-files $train_feat \
      --train-text-files $train_token_text \
      --valid-feat-files $valid_feat \
      --valid-text-files $valid_token_text \
      --dict $dict \
      --remove-bpe sentencepiece \
      --max-source-positions 9999 \
      --max-target-positions 999 $opts 2>&1 | tee $log_file
fi

if [ ${stage} -le 9 ]; then
  echo "Stage 9: Decoding"
  opts=""
  path=$dir/$checkpoint
  decode_affix=
  if $lm_shallow_fusion; then
    if ! $use_wordlm; then
      path="$path:$lmdir/$lm_checkpoint"
      opts="$opts --lm-weight 0.7 --coverage-weight 0.01"
      decode_affix=shallow_fusion
    else
      path="$path:$wordlmdir/$lm_checkpoint"
      opts="$opts --word-dict $wordlmdict --lm-weight 0.9 --oov-penalty 1e-7 --coverage-weight 0.0 --eos-factor 1.5"
      decode_affix=shallow_fusion_wordlm
    fi
  fi
  for dataset in $valid_set $test_set; do
      feat=${dumpdir}/${valid_set}/delta${do_delta}/feats.scp
    text=data/$dataset/token_text
    CUDA_VISIBLE_DEVICES=$(echo $free_gpu | sed 's/,/ /g' | awk '{print $1}') speech_recognize.py \
      --max-tokens 20000 --max-sentences 32 --num-shards 1 --shard-id 0 \
      --test-feat-files $feat --test-text-files $text \
      --dict $dict --non-lang-syms $nlsyms \
      --max-source-positions 9999 --max-target-positions 999 \
      --path $path --beam 50 --max-len-a 0.2 --max-len-b 0 --lenpen 1.0 \
      --results-path $dir/decode_$dataset${decode_affix:+_${decode_affix}} $opts \
      --print-alignment 2>&1 | tee $dir/logs/decode_$dataset${decode_affix:+_${decode_affix}}.log

    if $kaldi_scoring; then
      echo "verify WER by scoring with Kaldi..."
      local/score.sh data/$dataset $dir/decode_$dataset${decode_affix:+_${decode_affix}}
      cat $dir/decode_$dataset${decode_affix:+_${decode_affix}}/scoring_kaldi/wer
    fi
  done
fi
