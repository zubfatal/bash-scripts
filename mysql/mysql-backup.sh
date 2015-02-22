#!/bin/bash

### CONFIG ###
CONF_FILE_PER_TABLE=1
CONF_MYSQL_BIN=$( which mysql | tail -1 )
CONF_MYSQLDUMP_BIN=$( which mysqldump | tail -1 )
CONF_MYSQLDUMP_ARGS="--opt --allow-keywords"
CONF_TABLE_FILENAME="%DB%.%TABLE%"
CONF_DB_FILENAME="%DB%-%TIMESTAMP%"
CONF_TIMESTAMP_FORMAT="%Y%m%d_%H%M"
CONF_WORKDIR="./tmp"
CONF_BACKUP_DEST="."

### ARGUMENTS ###
ARG_DB=$1

### FUNCTIONS ###
function database_exists()
{
	local dbname=$1
	${CONF_MYSQL_BIN} -Bse "SHOW DATABASES LIKE '${dbname}';" | wc -l
}

function database_table_count()
{
	local dbname=$1
	${CONF_MYSQL_BIN} -Bse "SHOW TABLES FROM ${dbname};" 2>/dev/null | wc -l
}

function show_error()
{
	local error_type=$1
	local error_msg=$2
	local exit_code=${3:-0}

	case $( echo "${error_type}" | tr "[:upper:]" "[:lower:]" ) in
		warn)
			error_type="[WARN]"
			;;
		error)
			error_type="[ERROR]"
			;;
		info)
			error_type="[INFO]"
			;;
		debug)
			error_type="[DEBUG]"
			;;
		*)
			error_type="[UNKNOWN]"
	esac

	echo "${error_type} ${error_msg}"
	[[ ${exit_code} -ne 0 ]] && exit ${exit_code}
}

function show_syntax()
{
cat << EOF
Syntax: $( basename $0 ) <database>
EOF
}

function string_replace {
	#echo "${1/\*/$2}"
	echo "${1}" | sed "s/${2}/${3}/g"
}

function set_output_filename()
{
	local _timestamp=$( date +"${CONF_TIMESTAMP_FORMAT:-%Y%m%d_%H%M}" )
	local _dbname=$1
	local _tblname=$2

	[[ -z "${_tblname}" ]] && local output="${CONF_DB_FILENAME}" || local output="${CONF_TABLE_FILENAME}"

	output=$( string_replace "${output}" "%DB%" "${_dbname}" )
	output=$( string_replace "${output}" "%TABLE%" "${_tblname}" )
	output=$( string_replace "${output}" "%TIMESTAMP%" "${_timestamp}" )

	echo ${output}
}

### INIT ###
CONF_WORKDIR="${CONF_WORKDIR}/$$"					# set a random subdirectory to work in

# check executables and sufff
[[ ! -x ${CONF_MYSQL_BIN} ]] 						&& show_error "error" "MYSQL '${CONF_MYSQL_BIN}' not found or not executable." 1
[[ ! -x ${CONF_MYSQLDUMP_BIN} ]] 					&& show_error "error" "MYSQLDUMP '${CONF_MYSQLDUMP_BIN}' not found or not exetutable." 1
[[ -z "${ARG_DB}" ]]								&& show_syntax && exit 0
[[ $( database_exists "${ARG_DB}" ) -eq 0 ]]		&& show_error "info" "Database ${ARG_DB} does not exist." 1
[[ $( database_table_count "${ARG_DB}" ) -eq 0 ]]	&& show_error "info" "Database ${ARG_DB} has no tables, backup skipped." 1
[[ ! -d ${CONF_WORKDIR} ]]							&& mkdir -p ${CONF_WORKDIR}
[[ ! -d ${CONF_WORKDIR} ]]							&& show_error "info" "Work directory ${CONF_WORKDIR} not found, tried to created but failed :(" 1

### MAIN ###

if [ ${CONF_FILE_PER_TABLE:-0} -eq 1 ]; then
	backup_errors=0
	table_count=0

	for TABLE in $( ${CONF_MYSQL_BIN} -Bse "SHOW TABLES FROM ${ARG_DB};" ); do
		table_count=$(( table_count + 1 ))
		backup_filename=$( set_output_filename "${ARG_DB}" "${TABLE}" )
		backup_tmpname="${CONF_WORKDIR}/${backup_filename}"

		echo -n "Creating backup of ${ARG_DB}.${TABLE} into ${backup_filename} ... "

		${CONF_MYSQLDUMP_BIN} ${CONF_MYSQLDUMP_ARGS} ${ARG_DB} ${TABLE} 2>${backup_tmpname}.err 1>${backup_tmpname}.sql

		if [ $( cat ${CONF_WORKDIR}/${backup_filename}.err 2>/dev/null | wc -l ) -eq 0 ]; then
			rm ${backup_tmpname}.err
			echo "DONE"
		else
			echo "ERROR"
			backup_errors=$(( backup_errors + 1 ))
		fi
	done

	backup_saveas=$( set_output_filename "${ARG_DB}" )
	backup_saveas="${backup_saveas}.tgz"

	tar -C ${CONF_WORKDIR} --remove-files -czvf ${backup_saveas} .

	echo -n "Backup of ${ARG_DB} completed"
	[[ ${errors} -gt 0 ]] && echo -n ", with errors (${errors})"
	echo ". Saved as ${backup_saveas}"
else
	backup_filename=$( set_output_filename "${ARG_DB}" )
	backup_tmpname="${CONF_WORKDIR}/${backup_filename}"
	backup_saveas="${CONF_BACKUP_DEST}/${backup_filename}.sql.gz"
	backup_errors=0

	echo -n "Creating backup of ${ARG_DB} into ${backup_filename} ... "

	${CONF_MYSQLDUMP_BIN} ${CONF_MYSQLDUMP_ARGS} ${ARG_DB} 2>${backup_tmpname}.err 1>${backup_tmpname}.sql

	if [ $( cat ${backup_filename}.err 2>/dev/null | wc -l ) -eq 0 ]; then
		rm ${backup_tmpname}.err
		gzip -9 ${backup_tmpname}.sql
		mv ${backup_tmpname}.sql.gz ${backup_saveas}
		rm -Rf ${CONF_WORKDIR}
		echo "DONE"
	else
		echo "ERROR"
		backup_errors=$(( backup_errors + 1 ))
	fi

	echo -n "Backup of ${ARG_DB} completed"
	[[ ${errors} -gt 0 ]] && echo -n ", with errors (${errors})"
	echo ". Saved as ${backup_saveas}"
fi
