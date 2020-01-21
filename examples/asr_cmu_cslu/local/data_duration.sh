#! /bin/bash 

data_dir=$1
mkdir -p duration

if [ ! -f $data_dir/utt2dur ]; then
    ./utils/data/get_utt2dur.sh $data_dir
fi

echo "$data_dir"
python local/sum_duration.py $data_dir/utt2dur
echo ""


