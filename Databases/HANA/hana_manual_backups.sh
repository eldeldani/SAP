#!/bin/sh
# Created by daniel.munoz@global.ntt
# Please check below link for more info:
if [ "$#" -lt 2 ]; then
	echo "Usage $0 <HANA SYSTEM SID> <HANA TENANT SID>"
	exit 1
fi
sid=$1
tenant_sid=$2
backup_dir=/backup/hana/$HOSTNAME
backup_dir_systemdb=/backup/hana/$HOSTNAME/$sid/data/SYSTEMDB
backup_dir_tenant=/backup/hana/$HOSTNAME/$sid/data/DB_$tenant_sid
output_dir=$backup_dir/logs
date_timestamp=`date +%d%m%y_%H%M%S`
output_log_systemdb=$output_dir/SYSTEMDB_$date_timestamp
output_log_tenant=$output_dir/DB_$tenant_sid"_"$date_timestamp
hdbsql_path=/usr/sap/$sid/HDB??/exe/hdbsql

echo "sid: "$sid
echo "tenant_sid: "$tenant_sid
echo "backup_dir: "$backup_dir
echo "backup_dir_systemdb: "$backup_dir_systemdb
echo "backup_dir_tenant: "$backup_dir_tenant
echo "output_dir: "$output_dir
echo "output_log_systemdb: "$output_log_systemdb
echo "output_log_tenant: "$output_log_tenant
echo "hdbsql_path: "$hdbsql_path


#
echo "============================================================================================="  >> $output_log_systemdb 2>&1
echo "============================================================================================="  >> $output_log_tenant 2>&1
#
$hdbsql_path -U SYSTEMDB_BACKUP "BACKUP DATA USING FILE ('$backup_dir_systemdb/$date_timestamp"_"SYSTEMDB')" >> $output_log_systemdb 2>&1
$hdbsql_path -U SYSTEMDB_BACKUP "BACKUP DATA FOR $tenant_sid USING FILE ('$backup_dir_tenant/$date_timestamp"_"DB_$tenant_sid')" >> $output_log_tenant 2>&1