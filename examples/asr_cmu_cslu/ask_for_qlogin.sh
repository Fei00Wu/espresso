while true; do
    curr_running=$(qstat | grep QLOGIN | cut -d' ' -f8 | grep fwu)
    if [ ! -z $curr_running ]; then
        break
    else
        qlogin -l "hostname=c*,gpu=1,mem_free=12g,ram_free=12g" || (sleep 3m; continue);
    fi
done

