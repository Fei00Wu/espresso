#! /bin/bash
log=$1
grep "valid on" $log | cut -d'|' -f2,9 | sort -t' ' -k6 -n
