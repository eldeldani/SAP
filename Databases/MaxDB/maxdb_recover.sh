#!/bin/bash
# MaxDB Recovery Script
# Written by Daniel Munoz daniel.munoz@global.ntt on 22/06/22
if [ "$#" -ne 9 ]; then
        echo "Illegal number of parameters"
        echo "Usage:"
        echo "maxdb-recover.sh <host> <SID> <data backup prefix> <compressed> <# of files> <until date> <until time> <start nnn> <end nnn>
        where
         - host: Source host from the backup to recover
                 i.e.: nyr-hrmpl01
         - SID: Source SID from the backup to recover
                 i.e.: NHP
         - data backup date: As seen in backup directory from Production/backup/maxdb/<host>/<sid>/data/data_backup_<SID>-
           i.e.: 20220621_020004
         - compressed: yes or no
         - files: number of files if multifile is used. Set to 1 if single file.
         - until date: The until date you want for the recovery
           i.e.: 20220621
         - until time: Then until time you want for the recovery
           i.e.: 180000
         - start nnn: the log backup prefix required first after data recovery
         - end nnn: the last log backup prefix required for recovery
        "
        exit 1
fi
recovery_script=/tmp/maxdbrec.sql
rm -rf $recovery_script
host=$1
SID=$2
data_backup_prefix=$3
compressed=$4
files=$5
until_date=$6
until_time=$7
start_nnn=$8
end_nnn=$9
if [ "$compressed" == "yes" ];then
        if [ $(($files)) -gt 1 ]; then
                i=0
                while [ $i -ne $(($files)) ]; do
                        i=$(($i+1))
                        concat=$concat"FILE /backup/maxdb/"$host"/"$SID"/data/data_backup_"$SID"-"$3"_stripe"$i" COMPRESSED NAMED b"$i" "
                done
        else concat="FILE /backup/maxdb/"$host"/"$SID"/data/data_backup_"$SID"-"$3" COMPRESSED"
        fi
elif [ $(($files)) -gt 1 ]; then
                j=0
                while [ $j -ne $(($files)) ]; do
                        j=$(($j+1))
                        concat=$concat"FILE /backup/maxdb/"$host"/"$SID"/data/data_backup_"$SID"-"$3"_stripe"$j" NAMED b"$j" "
                done
        else concat="FILE /backup/maxdb/"$host"/"$SID"/data/data_backup_"$SID"-"$3
fi

echo "backup_template_create restore_$SID to "$concat" CONTENT DATA" >> $recovery_script
echo "backup_template_create LOG"$SID" to FILE /backup/maxdb/"$host"/"$SID"/autolog/LOG CONTENT LOG" >> $recovery_script
echo "db_admin" >> $recovery_script
echo "db_connect" >> $recovery_script
echo "recover_start restore_$SID DATA" >> $recovery_script
echo "db_admin" >> $recovery_script
echo "db_connect" >> $recovery_script
echo "util_execute clear log" >> $recovery_script
echo "db_admin" >> $recovery_script
echo "db_connect" >> $recovery_script
echo "recover_start LOG"$SID" log "$start_nnn" until "$until_date" "$until_time >> $recovery_script
#for ( i=$start_nnn; i<=$end_nnn; i++ ); do
loop=$((start_nnn))
while [ $loop -ne $end_nnn ]; do
        loop=$(($loop+1))
        echo "recover_replace LOG"$SID" /backup/maxdb/"$host"/"$SID"/autolog/LOG."$(printf "%03d" "$loop") >> $recovery_script
done

#echo "Backup template:"
#echo "backup_template_create restore_$SID to "$concat" CONTENT DATA"
#echo "Backup template log:"
#echo "backup_template_create LOG"$SID" to FILE /backup/maxdb/"$host"/"$SID"/autolog/LOG CONTENT LOG"
echo "===============INSTRUCTIONS====================="
echo "Run restore script with the below instructions"
echo "As sidadm:"
echo "dbmcli -U c -i "$recovery_script
