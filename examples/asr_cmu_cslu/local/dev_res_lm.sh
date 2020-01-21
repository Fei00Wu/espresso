log=$1
grep "valid on" $log | cut -d'|' -f2,5 | sort -t' ' -k6 -n
