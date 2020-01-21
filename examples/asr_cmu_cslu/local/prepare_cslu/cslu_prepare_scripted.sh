#/bin/bash 
# set -euo
# $1 = file to process
# $2 = scripted/spontaneous
# echo "    FileGen: $1 $2 $3"
audio=
data=data/cslu/scripted
log=data/cslu/scripted.log

. ./path.sh
. ./utils/parse_options.sh
# echo "$0 $@"

uttID=$(basename $audio)
uttID=${uttID%'.wav'}

sentID=${uttID: -3}
spkID=${uttID%$sentID}
sentID=${sentID%"0"}
sentID=$(echo "$sentID" | tr '[:lower:]' '[:upper:]' )

line=$(grep $sentID cslu/docs/all.map)

if [ -z "$line" ]; then     # Can't map utterance to transcript
    echo $audio $sentID >> $log
else
    txt=$(echo $line | grep -oP '"\K.*?(?=")')
    cap_txt=${txt^^}

    echo "$uttID $cap_txt" >> $data/text
    echo "$uttID $spkID" >> $data/utt2spk
    echo "$spkID f" >> $data/spk2gender
    echo "$uttID $audio" >> $data/wav.scp
fi


