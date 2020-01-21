#! /bin/bash

audio=$1
data=data/cslu/spontaneous
log=data/cslu/spontaneous.log

. ./utils/parse_options.sh
echo "$0 $@"

uttID=$(basename $audio)
uttID=${uttID%'.wav'}
spkID=${uttID%"xx0"}
if [ -z "$spkID" ]; then
    echo " #### $uttID"
fi
# Find transcript
trans=$(echo $audio | sed 's/speech/trans/g')
trans=${trans%".wav"}
trans+=".txt" 
tr '[:lower:]' '[:upper:]' < $trans | tr -d '[:cntrl:]' > out
txt=$(<out)

if [ -z "$txt" ];then
    echo $audio >> $debug
else
    echo "    $txt"
    # soxi -D $audio >> duration_spontaneous
    echo "$uttID $txt" >> $data/text
    echo "$uttID $spkID" >> $data/utt2spk
    echo "$spkID f" >> $data/spk2gender
    echo "$uttID $audio" >> $data/wav.scp
fi
