#! /bin/bash
set -euo

data=$1
python3 ./local/clean_apostrophe.py \
    --text_file $1/text \
    --out_file $1/new_text \
    --quote_file local/apostrophe_words
mkdir -p $1/.backup
mv $1/text $1/.backup/
mv $1/new_text $1/text
