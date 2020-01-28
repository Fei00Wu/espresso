#! /bin/bash
stage=0
ngpus=1 # num GPUs for multiple GPUs training within a single node; should match those in $free_gpu
free_gpu=`free-gpu` # comma-separated available GPU ids, eg., "0" or "0,1"; automatically assigned if on CLSP grid

# E2E model related
train_set=train_sent_spk
valid_set=dev_sent_spk
test_set="cmu_test_sent_spk cslu_test_sent_spk"
checkpoint=checkpoint_best.pt

# LM related
lm_checkpoint=checkpoint_best.pt

dumpdir=data/dump   # directory to dump full features

kaldi_scoring=true
# feature configuration
do_delta=false

dict=data/lang/train_960_unigram5000_units.txt
sentencepiece_model=data/lang/train_960_unigram5000
lmdict=$dict


lr=0.0003 # originally 0.001
freeze_parts="decoder"

lm_pretrained=exp/lm_lstm
lmdir=exp/lm_tuned
dir_pretrained=exp/lstm_wsj_untuned
dir=exp/lstm_tuned_wsj_lr-${lr}_freeze-$(echo $freeze_parts | tr ' ' '-')


. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh

train_feat_dir=${dumpdir}/${train_set}/delta${do_delta}; mkdir -p ${train_feat_dir}
valid_feat_dir=${dumpdir}/${valid_set}/delta${do_delta}; mkdir -p ${valid_feat_dir}
train_feat=$train_feat_dir/feats.scp
train_token_text=data/$train_set/token_text
vlid_subset=valid
valid_feat=$valid_feat_dir/feats.scp
valid_token_text=data/$valid_set/token_text


echo "Stage 8: Model Training"
    valid_subset=valid
    if [ ! -d $dir ]; then
        mkdir $dir
        mkdir -p $dir/logs
        cp $dir_pretrained/$checkpoint $dir/checkpoint_last.pt
    
    fi
    log_file=$dir/logs/train.log
    [ -f $dir/checkpoint_last.pt ] && log_file="-a $log_file"


CUDA_VISIBLE_DEVICES=$free_gpu speech_train.py --seed 1 \
        --freeze-parts $freeze_parts \
        --reset-lr-scheduler --reset-meters \
        --reset-dataloader --reset-optimizer \
        --task speech_recognition_espresso \
        --user-dir espresso \
        --log-interval 400 \
        --log-format simple \
        --print-training-sample-interval 1000 \
        --num-workers 0 \
        --max-tokens 24000 \
        --max-sentences 24 \
        --valid-subset valid \
        --max-sentences-valid 48 \
        --distributed-world-size 1 \
        --distributed-port $(if [ $ngpus -gt 1 ]; then echo 100; else echo -1; fi) \
        --ddp-backend no_c10d \
        --max-epoch 30 \
        --optimizer adam \
        --lr $lr \
        --weight-decay 0.0 \
        --clip-norm 2.0 \
        --lr-scheduler reduce_lr_on_plateau_v2 \
        --lr-shrink 0.5 \
        --start-reduce-lr-epoch 8 \
        --save-dir $dir \
        --restore-file checkpoint_last.pt \
        --save-interval-updates 400 \
        --keep-interval-updates 5 \
        --keep-last-epochs 5 \
        --validate-interval 1 \
        --best-checkpoint-metric wer \
        --arch speech_conv_lstm_wsj \
        --criterion label_smoothed_cross_entropy_v2 \
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
        --max-target-positions 999 2>&1 | tee $log_file

