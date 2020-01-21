set -euo
script=$1
stage=$2

script_name=$(basename $script | cut -d'.' -f1)
time_stamp=$(date +'%m_%d_%H_%M')

qsub -cwd -l "hostname=c*,gpu=1,mem_free=10g,ram_free=10g" \
    -q g.q -M fwu24@jhu.edu -m bea -e "results/${script_name}_stage${stage}_${time_stamp}.err" \
    -o "results/${script_name}_stage${stage}_${time_stamp}.out" \
    $script --stage $stage
