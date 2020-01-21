#! /bin/bash


printf "\t File Check in folder: %s.\n" "$1"

WavScp="$1/wav.scp"
Text="$1/text"
Utt2Spk="$1/utt2spk"
Gend="$1/utt2gender"
Spk2Utt="$1/spk2utt"

mkdir -p $1/.backup

for f in $WavScp $Text $Utt2Spk $Gend $Spk2Utt; do
    if [ -f $f ]; then
        echo "$f exist.  Moved to $1/.backup"
    fi
done




