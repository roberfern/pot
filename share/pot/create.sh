#!/bin/sh

create-help()
{
	echo "pot create [-hv] -p potname [-i ipaddr] [-l lvl] [-f flavour|-F]"
	echo '  [-b base | -P basepot ] [-d dns] [-t type]'
	echo '  -h print this help'
	echo '  -v verbose'
	echo '  -p potname : the pot name (mandatory)'
	echo '  -l lvl : pot level'
	echo '  -b base : the base pot'
	echo '  -P pot : the pot to be used as reference'
	echo '  -i ipaddr : an ip address'
	echo '  -s : static ip address'
	echo '  -d dns : one between inherit(default) or pot'
	echo '  -f flavour : flavour to be used'
	echo '  -F : no default flavour is used'
	echo '  -t type: single or multi (default multi)'
    echo '         single: the pot is based on a unique ZFS dataset'	
    echo '         multi: the pot is composed by a classical collection of 3 ZFS dataset'	
}

# $1 pot name
# $2 type
# $3 level
# $4 base name
# $5 pot-base name
_cj_zfs()
{
	local _pname _base _type _potbase _jdset _snap _dset
	_pname=$1
	_type=$2
	_lvl=$3
	_base=$4
	_potbase=$5
	_jdset=${POT_ZFS_ROOT}/jails/$_pname
	# Create the main jail zfs dataset
	if ! _zfs_dataset_valid "$_jdset" ; then
		zfs create "$_jdset"
	else
		_info "$_jdset exists already"
	fi
	if [ "$_type" = "single" ]; then
		if [ -z "$_potbase" ]; then
			# create an empty dataset
			zfs create "$_jdset/m"
			# create the minimum needed tree
			mkdir -p "${POT_FS_ROOT}/jails/$_pname/m/tmp"
			mkdir -p "${POT_FS_ROOT}/jails/$_pname/m/dev"
		else
			# clone the last snapshot of _potbase
			_dset=${POT_ZFS_ROOT}/jails/$_potbase/m
			_snap=$(_zfs_last_snap "$_dset")
			if [ -n "$_snap" ]; then
				_debug "Clone zfs snapshot $_dset@$_snap"
				zfs clone -o mountpoint="${POT_FS_ROOT}/jails/$_pname/m" "$_dset/@$_snap" "$_jdset/m"
			else
				# TODO - autofix
				_error "no snapshot found for $_dset/m"
				return 1 # false
			fi
		fi
		return 0
	# Create the root mountpoint
	elif [ ! -d "${POT_FS_ROOT}/jails/$_pname/m" ]; then
		mkdir -p "${POT_FS_ROOT}/jails/$_pname/m"
	fi

	# lvl 0 images mount directly usr.local and custom
	if [ "$_lvl" = "0" ]; then
		return 0 # true
	fi

	# usr.local
	if [ $_lvl -eq 1 ]; then
		# lvl 1 images clone usr.local dataset
		if ! _zfs_dataset_valid $_jdset/usr.local ; then
			if [ -n "$_potbase" ]; then
				_dset=${POT_ZFS_ROOT}/jails/$_potbase
			else
				_dset=${POT_ZFS_ROOT}/bases/$_base
			fi
			_snap=$(_zfs_last_snap $_dset/usr.local)
			if [ -n "$_snap" ]; then
				_debug "Clone zfs snapshot $_dset/usr.local@$_snap"
				zfs clone -o mountpoint=${POT_FS_ROOT}/jails/$_pname/usr.local $_dset/usr.local@$_snap $_jdset/usr.local
			else
				# TODO - autofix
				_error "no snapshot found for $_dset/usr.local"
				return 1 # false
			fi
		else
			_info "$_jdset/usr.local exists already"
		fi
	fi

	# custom dataset
	if ! _zfs_dataset_valid $_jdset/custom ; then
		if [ -n "$_potbase" ]; then
			_dset=${POT_ZFS_ROOT}/jails/$_potbase/custom
		else
			_dset=${POT_ZFS_ROOT}/bases/$_base/custom
		fi
		_snap=$(_zfs_last_snap $_dset)
		if [ -n "$_snap" ]; then
			_debug "Clone zfs snapshot $_dset@$_snap"
			zfs clone -o mountpoint=${POT_FS_ROOT}/jails/$_pname/custom $_dset@$_snap $_jdset/custom
		else
			# TODO - autofix
			_error "no snapshot found for $_dset"
			return 1 # false
		fi
	else
		_info "$_jdset/custom exists already"
	fi
	return 0 # true
}

# $1 pot name
# $2 base name
# $3 ip
# $4 static_ip
# $5 level
# $6 dns
# $7 type
# $8 pot-base name
_cj_conf()
{
	local _pname _base _ip _staticip _lvl _jdir _bdir _potbase _dns _type
	local _pblvl _pbpb
	local _jdset _bdset _pbdset _baseos
	_pname=$1
	_base=$2
	_ip=$3
	_staticip=$4
	_lvl=$5
	_dns=$6
	_type=$7
	_potbase=$8
	_jdir=${POT_FS_ROOT}/jails/$_pname
	_bdir=${POT_FS_ROOT}/bases/$_base

	_jdset=${POT_ZFS_ROOT}/jails/$_pname
	_bdset=${POT_ZFS_ROOT}/bases/$_base
	if [ -n "$_potbase" ]; then
		_pblvl=$( _get_conf_var $_potbase pot.level )
		_pbdset=${POT_ZFS_ROOT}/jails/$_potbase
	else
		_pblvl=
	fi
	if [ ! -d $_jdir/conf ]; then
		mkdir -p $_jdir/conf
	fi
	(
	if [ "$_type" = "multi" ]; then
		case $_lvl in
		0)
			echo "$_bdset ${_jdir}/m"
			echo "$_bdset/usr.local ${_jdir}/m/usr/local"
			echo "$_bdset/custom ${_jdir}/m/opt/custom"
			;;
		1)
			echo "$_bdset ${_jdir}/m ro"
			echo "$_jdset/usr.local ${_jdir}/m/usr/local zfs-remount"
			echo "$_jdset/custom ${_jdir}/m/opt/custom zfs-remount"
			;;
		2)
			echo "$_bdset ${_jdir}/m ro"
			if [ $_pblvl -eq 1 ]; then
				echo "$_pbdset/usr.local ${_jdir}/m/usr/local ro"
			else
				_pbpb=$( _get_conf_var $_potbase pot.potbase )
				echo "${POT_ZFS_ROOT}/jails/$_pbpb/usr.local ${_jdir}/m/usr/local ro"
			fi
			echo "$_jdset/custom ${_jdir}/m/opt/custom zfs-remount"
			;;
		esac
	fi
	) > $_jdir/conf/fscomp.conf
	(
		_baseos=$( cat $_bdir/.osrelease )
		echo "pot.level=${_lvl}"
		echo "pot.type=${_type}"
		echo "pot.base=${_base}"
		echo "pot.potbase=${_potbase}"
		echo "pot.dns=${_dns}"
		echo "pot.cmd=sh /etc/rc"
		echo "host.hostname=\"${_pname}.$( hostname )\""
		echo "osrelease=\"${_baseos}-RELEASE\""
		if [ "$_ip" = "inherit" ]; then
			echo "ip4=inherit"
			echo "vnet=false"
		else
			if [ $_staticip = "YES" ]; then
				echo "ip4=${_ip}"
				echo "vnet=false"
			else
				echo "ip4=${_ip}"
				echo "vnet=true"
			fi
		fi
		if [ "${_dns}" = "pot" ]; then
			echo "pot.depend=${POT_DNS_NAME}"
		fi
	) > $_jdir/conf/pot.conf
	if [ "$_lvl" -eq 2 ]; then
		if [ $_pblvl -eq 1 ]; then
			# CHANGE the potbase usr.local to be not zfs-remount
			# Add an info here would be nice
			if [ -w "${POT_FS_ROOT}/jails/$_potbase/conf/fscomp.conf" ]; then
				_info "${POT_FS_ROOT}/jails/$_potbase/conf/fscomp.conf fix (${POT_FS_ROOT}/jails/$_potbase/m/usr/local zfs-remount)"
				${SED} -i '' s%${POT_FS_ROOT}/jails/$_potbase/m/usr/local\ zfs-remount%${POT_FS_ROOT}/jails/$_potbase/m/usr/local% ${POT_FS_ROOT}/jails/$_potbase/conf/fscomp.conf
			else
				_info "$_potbase fscomp.conf has not fscomp.conf"
			fi
		fi
	fi
	# disable some cron jobs, not relevant in a jail
	if [ "$_lvl" -ne 0 ]; then
		${SED} -i '' 's/^.*save-entropy$/# &/g' "${_jdir}/custom/etc/crontab"
		${SED} -i '' 's/^.*adjkerntz.*$/# &/g' "${_jdir}/custom/etc/crontab"
	fi

	if [ "$_type" = "multi" ]; then
		# add remote syslogd capability, if not inherit
		if [ "$_ip" != "inherit" ]; then
			# Creating the needed folders on need.
			mkdir -p /usr/local/etc/syslog.d /usr/local/etc/newsyslog.conf.d /var/log/pot

			# configure syslog in the pot
			${SED} -i '' 's%^[^#].*/var/log.*$%# &%g' "${_jdir}/custom/etc/syslog.conf"
			echo "*.*  @${POT_GATEWAY}:514" > "${_jdir}/custom/etc/syslog.d/pot.conf"
			sysrc -f "${_jdir}/custom/etc/rc.conf" "syslogd_flags=-vv -s -b $_ip"
			# configure syslogd in the host
			(
				echo +"$_ip"
				echo '*.*		'"/var/log/pot/${_pname}.log"
			) > /usr/local/etc/syslog.d/"${_pname}".conf
			touch /var/log/pot/"${_pname}".log
			(
				echo "# log rotation for pot ${_pname}"
				echo "/var/log/pot/${_pname}.log 644 7 * @T00 CX"
			) > /usr/local/etc/newsyslog.conf.d/"${_pname}".conf
			service syslogd reload
		fi
	fi
}

# $1 pot name
# $2 flavour name
_cj_flv()
{
	local _pname _flv _pdir
	_pname=$1
	_flv=$2
	_pdir=${POT_FS_ROOT}/jails/$_pname
	_debug "Flavour: $_flv"
	if [ -r ${_POT_FLAVOUR_DIR}/${_flv} ]; then
		_debug "Adopt $_flv for $_pname"
		while read -r line ; do
			if _is_cmd_flavorable $line ; then
				pot-cmd $line -p $_pname
			else
				_error "Flavor $_flv: line $line not valid - ignoring"
			fi
		done < ${_POT_FLAVOUR_DIR}/${_flv}
	fi
	if [ -x ${_POT_FLAVOUR_DIR}/${_flv}.sh ]; then
		_debug "Start $_pname pot for the initial bootstrap"
		pot-cmd start $_pname
		cp -v ${_POT_FLAVOUR_DIR}/${_flv}.sh $_pdir/m/tmp
		jexec $_pname /tmp/${_flv}.sh $_pname
		pot-cmd stop $_pname
	else
		_debug "No shell script available for the flavour $_flv"
	fi
}

pot-create()
{
	local _pname _ipaddr _lvl _base _flv _potbase
	local _flv_default _dns _staticip _type
	_pname=
	_base=
	_ipaddr=inherit
	_lvl=1
	_flv=
	_potbase=
	_flv_default="YES"
	_dns=inherit
	_staticip="NO"
	_type="multi"
	if ! args=$(getopt hvp:i:sl:b:f:P:Fd:t: "$@") ; then
		create-help
		${EXIT} 1
	fi
	set -- $args
	while true; do
		case "$1" in
		-h)
			create-help
			${EXIT} 0
			;;
		-v)
			_POT_VERBOSITY=$(( _POT_VERBOSITY + 1))
			shift
			;;
		-p)
			_pname=$2
			shift 2
			;;
		-i)
			_ipaddr=$2
			shift 2
			;;
		-s)
			_staticip="YES"
			shift
			;;
		-l)
			_lvl=$2
			shift 2
			;;
		-t)
			if [ "$2" = "multi" ] || [ "$2" = "single" ]; then
				_type="$2"
			else
				_error "Type $2 not supported"
				create-help
				${EXIT} 1
			fi
			shift 2
			;;
		-b)
			_base=$2
			shift 2
			;;
		-P)
			_potbase=$2
			shift 2
			;;
		-f)
			if [ -z "${_POT_FLAVOUR_DIR}" -o ! -d "${_POT_FLAVOUR_DIR}" ]; then
				_error "The flavour dir is missing"
				${EXIT} 1
			fi
			if [ -r "${_POT_FLAVOUR_DIR}/$2" -o -x "${_POT_FLAVOUR_DIR}/$2.sh" ]; then
				_flv=$2
			else
				_error "The flavour $2 not found"
				_debug "Looking in the flavour dir ${_POT_FLAVOUR_DIR}"
				${EXIT} 1
			fi
			shift 2
			;;
		-F)
			_flv_default="NO"
			shift
			;;
		-d)
			case $2 in
				"inherit")
					;;
				"pot")
					_dns=pot
					;;
				*)
					_error "The dns $2 is not a valid option: choose between inherit or pot"
					create-help
					${EXIT} 1
			esac
			shift 2
			;;
		--)
			shift
			break
			;;
		esac
	done

	# check options consitency
	if [ "$_type" = "single" ]; then
		_lvl=0
		_flv_default="NO"
		if [ -n "$_potbase" ]; then
			if ! is_pot "$_potbase" quiet ; then
				_error "pot $_potbase not found"
				${EXIT} 1
			fi
			if [ "$( _get_pot_type "$_potbase" )" != "single" ]; then
				_error "pot $_potbase has the wrong type, it as to be of type single"
				${EXIT} 1
			fi
			if [ -z "$_base" ]; then
				_base="$( _get_pot_base "$_potbase" )"
			elif [ "$( _get_pot_base "$_potbase" )" != "$_base" ]; then
				_error "-b $_base and -P $_potbase are not compatible"
				create-help
				${EXIT} 1
			fi
		else
		   	if [ -z "$_base" ]; then
				_error "at least one of -b and -P has to be used"
				create-help
				${EXIT} 1
			fi
			if ! _is_base "$_base" quiet ; then
				_error "$_base is not a valid base"
				create-help
				${EXIT} 1
			fi
		fi
	else
		case $_lvl in
				0)
				if [ -z "$_base" ]; then
					_error "level $_lvl needs option -b"
					create-help
					${EXIT} 1
				fi
				if [ -n "$_potbase" ]; then
					_error "-P option is not allowed with level $_lvl"
					create-help
					${EXIT} 1
				fi
				if ! _is_base "$_base" quiet ; then
					_error "$_base is not a valid base"
					create-help
					${EXIT} 1
				fi
				;;
			1)
				if [ -z "$_base" -a -z "$_potbase" ]; then
					_error "at least one of -b and -P has to be used"
					create-help
					${EXIT} 1
				fi
				if [ -n "$_base" -a -n "$_potbase" ]; then
					if [ "$( _get_pot_base $_potbase )" != "$_base" ]; then
						_error "-b $_base and -P $_potbase are not compatible"
						create-help
						${EXIT} 1
					fi
					# TODO: an info or debug message che be showned
				fi
				if [ -n "$_potbase" ]; then
					if ! _is_pot $_potbase ; then
						_error "-P $_potbase : is not a pot"
						create-help
						${EXIT} 1
					fi
					if [ "$( _get_conf_var $_potbase pot.level )" != "1" ]; then
						_error "-P $_potbase : it has to be of level 1"
						create-help
						${EXIT} 1
					fi
				fi
				if [ -z "$_base" ]; then
					_base=$( _get_pot_base $_potbase )
					if [ -z "$_base" ]; then
						_error "-P $potbase has no base??"
						${EXIT} 1
					fi
					_debug "-P $_potbase induced -b $_base"
				fi
				if ! _is_base "$_base" quiet ; then
					_error "$_base is not a valid base"
					create-help
					${EXIT} 1
				fi
				;;
			2)
				if [ -z "$_potbase" ]; then
					_error "level $_lvl pots need another pot as reference"
					create-help
					${EXIT} 1
				fi
				if [ $( _get_conf_var $_potbase pot.level ) -lt 1 ]; then
					_error "-P $_potbase : it has to be at least of level 1"
					create-help
					${EXIT} 1
				fi
				if ! _is_pot $_potbase ; then
					_error "-P $_potbase : is not a pot"
					create-help
					${EXIT} 1
				fi
				if [ -n "$_base" ]; then
					if ! _is_base "$_base" quiet ; then
						_error "$_base is not a valid base"
						create-help
						${EXIT} 1
					fi
					if [ "$( _get_pot_base $_potbase )" != "$_base" ]; then
						_error "-b $_base and -P $_potbase are not compatible"
						${EXIT} 1
					fi
				else
					_base=$( _get_pot_base $_potbase )
					if [ -z "$_base" ]; then
						_error "-P $potbase has no base??"
						${EXIT} 1
					fi
					if ! _is_base "$_base" quiet ; then
						_error "$_base (induced by the pot $_potbase) is not a valid base"
						create-help
						${EXIT} 1
					fi
				fi
				;;
			*)
				_error "level $_lvl is not supported"
				${EXIT} 1
				;;
		esac
	fi
	if [ -z "$_pname" ]; then
		_error "pot name is missing"
		create-help
		${EXIT} 1
	fi
	if _is_pot "$_pname" quiet ; then
		_error "pot $_pname already exists"
		${EXIT} 1
	fi
	if [ "$_ipaddr" = "inherit" ] && [ $_staticip = "YES" ]; then
		_info "-s option is ignored if -i is inherit"
		_staticip="NO"
	fi
	if ! _is_uid0 ; then
		${EXIT} 1
	fi
	if [ "$_ipaddr" != "inherit" ]; then
		if [ "$_staticip" != "YES" ]; then
			if ! _is_vnet_available ; then
				_error "This kernel doesn't support VIMAGE! No vnet possible"
				${EXIT} 1
			fi
			if ! _is_vnet_up ; then
				_info "No pot bridge found! Calling vnet-start to fix the issue"
				pot-cmd vnet-start
			fi
		fi
	fi
	if [ "$_dns" = "pot" ]; then
		if ! _is_vnet_available ; then
			_error "This kernel doesn't support VIMAGE! No vnet possible (needed by the dns)"
			${EXIT} 1
		fi
		if ! _is_pot "${POT_DNS_NAME}" quiet ; then
			_info "dns pot not found ($POT_DNS_NAME) - fixing"
			pot-cmd create-dns
		fi
	fi
	if _is_verbose ; then
		_info "Option summary"
		_info "pname : $_pname"
		_info "type  : $_type"
		_info "base  : $_base"
		_info "lvl   : $_lvl"
		_info "dns   : $_dns"
		_info "pbase : $_potbase"
		_info "ip    : $_ipaddr"
		_info "ip alias : $_staticip"
	fi
	if ! _cj_zfs "$_pname" "$_type" "$_lvl" "$_base" "$_potbase" ; then
		${EXIT} 1
	fi
	if ! _cj_conf "$_pname" "$_base" "$_ipaddr" "$_staticip" "$_lvl" "$_dns" "$_type" "$_potbase" ; then
		${EXIT} 1
	fi
	if [ $_flv_default = "YES" ]; then
		_cj_flv $_pname default
	fi
	if [ -n "$_flv" ]; then
		_cj_flv $_pname $_flv
	fi
}
