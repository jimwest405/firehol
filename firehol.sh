#!/bin/sh
#
# Startup script to implement /etc/firehol.conf pre-defined rules.
#
# chkconfig: 2345 99 92
#
# description: Automates a packet filtering firewall with iptables.
#
# by costa@tsaousis.gr
#
# config: /etc/firehol.conf

# ------------------------------------------------------------------------------
# Copied from /etc/init.d/iptables

# On on RedHat machines we need success and failure
success() {
	echo " OK"
}
failure() {
	echo " FAILED"
}

test -f /etc/init.d/functions && . /etc/init.d/functions

if [ ! -x /sbin/iptables ]; then
	exit 0
fi

KERNELMAJ=`uname -r | sed                   -e 's,\..*,,'`
KERNELMIN=`uname -r | sed -e 's,[^\.]*\.,,' -e 's,\..*,,'`

if [ "$KERNELMAJ" -lt 2 ] ; then
	exit 0
fi
if [ "$KERNELMAJ" -eq 2 -a "$KERNELMIN" -lt 3 ] ; then
	exit 0
fi


if  /sbin/lsmod 2>/dev/null |grep -q ipchains ; then
	# Don't do both
	exit 0
fi

# --- PARAMETERS Processing ----------------------------------------------------

# The default configuration file
FIREHOL_CONFIG="/etc/firehol.conf"

# If set to 1, we are just going to present the resulting firewall instead of
# installing it.
FIREHOL_DEBUG=0

# If set to 1, the firewall will be saved for normal iptables processing.
FIREHOL_SAVE=0


arg="${1}"
shift

if [ ! -z "${arg}" -a -f "${arg}" ]
then
	FIREHOL_CONFIG="${arg}"
	arg="start"
fi

if [ ! -f "${FIREHOL_CONFIG}" ]
then
	echo -n $"FireHOL config ${FIREHOL_CONFIG} not found:"
	failure $"FireHOL config ${FIREHOL_CONFIG} not found:"
	echo
	exit 1
fi

case "${arg}" in
	start)
		;;
	
	restart)
		;;
	
	condrestart)
		if [ ! -e /var/lock/subsys/iptables ]
		then
			exit 0
		fi
		;;
	
	save)
		FIREHOL_SAVE=1
		;;
		
	debug)
		FIREHOL_DEBUG=1
		;;
	
	*)
		echo >&2 "FireHOL: Calling the iptables service..."
		/etc/init.d/iptables "$@"
		ret=$?
		if [ $ret -gt 0 ]
		then
			echo >&2 "FireHOL: use also the 'debug' parameter to test your script."
		fi
		exit $ret
		;;
esac
shift


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# GLOBAL DEFAULTS
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------

# The default policy for the firewall.
# If you decide to change this, make sure this does not allow access
# (i.e. use DROP, REJECT, MIRROR, etc. - not ACCEPT, RETURN, etc).
DEFAULT_INTERFACE_POLICY="DROP"

# The client ports to be used for "default" client ports when the client
# specified is a foreign host.
# We give all ports above 1000 because a few systems (like Solaris) use this range.
DEFAULT_CLIENT_PORTS="1000:65535"

# Get the default client ports from the kernel configuration.
# This is formed to a range of ports to be used for all "default" client ports
# when the client specified is the localhost.
LOCAL_CLIENT_PORTS_LOW=`sysctl net.ipv4.ip_local_port_range | cut -d '=' -f 2 | cut -f 1`
LOCAL_CLIENT_PORTS_HIGH=`sysctl net.ipv4.ip_local_port_range | cut -d '=' -f 2 | cut -f 2`
LOCAL_CLIENT_PORTS=`echo ${LOCAL_CLIENT_PORTS_LOW}:${LOCAL_CLIENT_PORTS_HIGH}`

# These files will be created and deleted during our run.
FIREHOL_OUTPUT="/tmp/firehol-out-$$.sh"
FIREHOL_SAVED="/tmp/firehol-save-$$.sh"
FIREHOL_TMP="/tmp/firehol-tmp-$$.sh"

# This is our version number. It is increased when the configuration file commands
# and arguments change their meaning and usage, so that the user will have to review
# it more precisely.
FIREHOL_VERSION=4
FIREHOL_VERSION_CHECKED=0

FIREHOL_LINEID="INIT"

# ------------------------------------------------------------------------------
# Keep information about the current primary command
# Primary commands are: interface, router

work_cmd=
work_name=
work_policy=${DEFAULT_INTERFACE_POLICY}
work_error=0


# ------------------------------------------------------------------------------
# Keep status information

# Keeps a list of all interfaces we have setup rules
work_interfaces=

# 0 = no errors, 1 = there were errors in the script
work_final_status=0

# keeps a list of all created iptables chains
work_created_chains=


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# SIMPLE SERVICES DEFINITIONS
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
# The following are definitions for simple services.
# We define as "simple" the services that are implemented using a single socket,
# initiated by the client and used by the server.

server_smtp_ports="tcp/smtp"
client_smtp_ports="default"

server_ident_ports="tcp/auth"
client_ident_ports="default"

server_dns_ports="tcp/domain udp/domain"
client_dns_ports="default domain"

server_imap_ports="tcp/imap"
client_imap_ports="default"

server_pop3_ports="tcp/pop3"
client_pop3_ports="default"

server_ssh_ports="tcp/ssh"
client_ssh_ports="default"

server_telnet_ports="tcp/telnet"
client_telnet_ports="default"

server_tftp_ports="tcp/tftp"
client_tftp_ports="default"

server_dhcp_ports="udp/bootps"
client_dhcp_ports="bootpc"

server_ldap_ports="tcp/ldap"
client_ldap_ports="default"

server_http_ports="tcp/http"
client_http_ports="default"

server_https_ports="tcp/https"
client_https_ports="default"

server_mysql_ports="tcp/mysql"
client_mysql_ports="default"

server_lpd_ports="tcp/printer"
client_lpd_ports="default"

server_radius_ports="udp/radius udp/radius-acct"
client_radius_ports="default"

server_radiusold_ports="udp/1645 udp/1646"
client_radiusold_ports="default"

server_vmware_ports="tcp/902"
client_vmware_ports="default"

server_netbios_ns_ports="udp/netbios-ns"
client_netbios_ns_ports="default udp/netbios-ns"

server_netbios_dgm_ports="udp/netbios-dgm"
client_netbios_dgm_ports="default netbios-dgm"

server_netbios_ssn_ports="tcp/netbios-ssn"
client_netbios_ssn_ports="default"

server_syslog_ports="udp/syslog"
client_syslog_ports="syslog"

server_snmp_ports="udp/snmp"
client_snmp_ports="default"

server_ntp_ports="udp/ntp"
client_ntp_ports="ntp"

# Portmap clients appear to use ports bellow 1024
server_portmap_ports="udp/sunrpc tcp/sunrpc"
client_portmap_ports="500:65535"

# We assume heartbeat uses ports in the range 690 to 699
server_heartbeat_ports="udp/690:699"
client_heartbeat_ports="default"


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# COMPLEX SERVICES DEFINITIONS
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
# The following are definitions for complex services.
# We define as "complex" the services that are implemented using multiple sockets.

# Each function bellow is organized in three parts:
# 1) A Header, common to each and every function
# 2) The rules required for the INPUT of the server
# 3) The rules required for the OUTPUT of the server
#
# The Header part, together with the "reverse" keyword can reverse the rules so
# that if we are implementing a client the INPUT will become OUTPUT and vice versa.
#
# In most the cases the input and output rules are the same with the following
# differences:
#
# a) The output rules begin with the "reverse" keyword, which reverses:
#    inface/outface, src/dst, sport/dport
# b) The output rules use ${out}_${mychain} instead of ${in}_${mychain}
# c) The state rules match the client operation, not the server.


# --- SAMBA --------------------------------------------------------------------

rules_samba() {
	local type="${1}"; shift
	
	local mychain="${work_name}_samba_${type}"
	
	create_chain in_${mychain} in_${work_name}
	create_chain out_${mychain} out_${work_name}
	
	local in=in
	local out=out
	if [ "${type}" = "route" -o "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule action "$@" chain "${in}_${mychain}" proto "udp" sport "netbios-ns ${client_ports}"  dport "netbios-ns" state NEW,ESTABLISHED || return 1
	rule action "$@" chain "${in}_${mychain}" proto "udp" sport "netbios-dgm ${client_ports}" dport "netbios-dgm" state NEW,ESTABLISHED || return 1
	rule action "$@" chain "${in}_${mychain}" proto "tcp" sport "${client_ports}" dport "netbios-ssn" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule reverse action "$@" chain "${out}_${mychain}" proto "udp" sport "netbios-ns ${client_ports}"  dport "netbios-ns" state ESTABLISHED || return 1
	rule reverse action "$@" chain "${out}_${mychain}" proto "udp" sport "netbios-dgm ${client_ports}" dport "netbios-dgm" state ESTABLISHED || return 1
	rule reverse action "$@" chain "${out}_${mychain}" proto "tcp" sport "${client_ports}" dport "netbios-ssn" state ESTABLISHED || return 1
	
	return 0
}


# --- PPTP --------------------------------------------------------------------

rules_pptp() {
	local type="${1}"; shift
	
	local mychain="${work_name}_pptp_${type}"
	
	create_chain in_${mychain} in_${work_name}
	create_chain out_${mychain} out_${work_name}
	
	local in=in
	local out=out
	if [ "${type}" = "route" -o "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule action "$@" chain "${in}_${mychain}" proto "tcp" sport "${client_ports}" dport "1723" state NEW,ESTABLISHED || return 1
	rule action "$@" chain "${in}_${mychain}" proto "47" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule reverse action "$@" chain "${out}_${mychain}" proto "tcp" sport "${client_ports}" dport "1723" state ESTABLISHED || return 1
	rule reverse action "$@" chain "${out}_${mychain}" proto "47" state ESTABLISHED|| return 1
	
	return 0
}


# --- NFS ----------------------------------------------------------------------

rules_nfs() {
	local type="${1}"; shift
	
	local mychain="${work_name}_nfs_${type}"
	
	create_chain in_${mychain} in_${work_name}
	create_chain out_${mychain} out_${work_name}
	
	local in=in
	local out=out
	if [ "${type}" = "route" -o "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# This command requires in the client or route subcommands,
	# the first argument after the policy/action is a dst.
	
	local action="${1}"; shift
	local servers="localhost"
	
	if [ "${type}" = "route" -o "${type}" = "client" ]
	then
		case "${1}" in
			dst|DST|destination|DESTINATION)
				shift
				servers="${1}"
				shift
				;;
				
			*)
				error "Please re-phrase to: ${type} nfs ${action} dst <NFS_SERVER> [other rules]"
				return 1
				;;
		esac
	fi
	
	local x=
	for x in ${servers}
	do
		local tmp="/tmp/firehol.rpcinfo.$$"
		
		rpcinfo -p ${x} >"${tmp}"
		if [ $? -gt 0 -o ! -s "${tmp}" ]
		then
			error "Cannot get rpcinfo from host '${x}' (using the previous firewall rules)"
			rm -f "${tmp}"
			return 1
		fi
		
		local server_mountd_ports="`cat "${tmp}" | grep " mountd$" | ( while read a b proto port s; do echo "$proto/$port"; done ) | sort | uniq`"
		local server_nfsd_ports="`cat "${tmp}" | grep " nfs$" | ( while read a b proto port s; do echo "$proto/$port"; done ) | sort | uniq`"
		
		local dst=
		if [ ! "${x}" = "localhost" ]
		then
			dst="dst ${x}"
		fi
		
		rules_custom "${type}" nfs "${server_mountd_ports}" "500:65535" "${action}" $dst "$@"
		rules_custom "${type}" nfs "${server_nfsd_ports}"   "500:65535" "${action}" $dst "$@"
		
		rm -f "${tmp}"
		
		echo >&2 ""
		echo >&2 "WARNING:"
		echo >&2 "This firewall must be restarted if NFS server ${x} is restarted !!!"
		echo >&2 ""
	done
	
	return 0
}


# --- ALL ----------------------------------------------------------------------

rules_all() {
	local type="${1}"; shift
	
	local mychain="${work_name}_all_${type}"
	
	create_chain in_${mychain} in_${work_name}
	create_chain out_${mychain} out_${work_name}
	
	local in=in
	local out=out
	if [ "${type}" = "route" -o "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule action "$@" chain ${in}_${mychain} state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule reverse action "$@" chain ${out}_${mychain} state ESTABLISHED || return 1
	
	"${type}" icmp "$@"
	"${type}" ftp "$@"
	
	return 0
}


# --- FTP ----------------------------------------------------------------------

rules_ftp() {
	local type="${1}"; shift
	
	local mychain="${work_name}_ftp_${type}"
	
	create_chain in_${mychain} in_${work_name}
	create_chain out_${mychain} out_${work_name}
	
	local in=in
	local out=out
	if [ "${type}" = "route" -o "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming, and established outgoing
	# accept port ftp new connections
	rule action "$@" chain ${in}_${mychain} proto tcp sport ${client_ports} dport ftp state NEW,ESTABLISHED || return 1
	rule reverse action "$@" chain ${out}_${mychain} proto tcp sport ${client_ports} dport ftp state ESTABLISHED || return 1
	
	# Active FTP
	# send port ftp-data related connections
	rule action "$@" chain ${out}_${mychain} proto tcp sport ftp-data dport ${client_ports} state ESTABLISHED,RELATED || return 1
	rule reverse action "$@" chain ${in}_${mychain} proto tcp sport ftp-data dport ${client_ports} state ESTABLISHED || return 1
	
	# ----------------------------------------------------------------------
	
	# A hack for Passive FTP only
	local s_client_ports="${DEFAULT_CLIENT_PORTS}"
	local c_client_ports="${DEFAULT_CLIENT_PORTS}"
	
	if [ "${type}" = "client" ]
	then
		c_client_ports="${LOCAL_CLIENT_PORTS}"
	elif [ "${type}" = "server" ]
	then
		s_client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# Passive FTP
	# accept high-ports related connections
	rule action "$@" chain ${in}_${mychain} proto tcp sport ${c_client_ports} dport ${s_client_ports} state ESTABLISHED,RELATED || return 1
	rule reverse action "$@" chain ${out}_${mychain} proto tcp sport ${c_client_ports} dport ${s_client_ports} state ESTABLISHED || return 1
	
	return 0
}


# --- ICMP ---------------------------------------------------------------------

rules_icmp() {
	local type="${1}"; shift
	
	local mychain="${work_name}_icmp_${type}"
	
	create_chain in_${mychain} in_${work_name}
	create_chain out_${mychain} out_${work_name}
	
	local in=in
	local out=out
	if [ "${type}" = "route" -o "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# check out http://www.cs.princeton.edu/~jns/security/iptables/iptables_conntrack.html#ICMP
	
	# allow new and established incoming packets
	rule action "$@" chain ${in}_${mychain} proto icmp state NEW,ESTABLISHED,RELATED || return 1
	
	# allow outgoing established packets
	rule reverse action "$@" chain ${out}_${mychain} proto icmp state ESTABLISHED,RELATED || return 1
	
	return 0
}

# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# INTERNAL FUNCTIONS BELLOW THIS POINT
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Check our version

version() {
	FIREHOL_VERSION_CHECKED=1
	
	if [ ${1} -gt ${FIREHOL_VERSION} ]
	then
		error "Wrong version. FireHOL is v${FIREHOL_VERSION}, your script requires v${1}."
	fi
}


# ------------------------------------------------------------------------------
# Make sure we cleanup when we exit.
# We trap this, so even a CTRL-C will call this and we will not leave tmp files.

firehol_exit() {
	test -f "${FIREHOL_OUTPUT}"	&& rm -f "${FIREHOL_OUTPUT}"
	test -f "${FIREHOL_OUTPUT}.log"	&& rm -f "${FIREHOL_OUTPUT}.log"
	test -f "${FIREHOL_SAVED}"	&& rm -f "${FIREHOL_SAVED}"
	test -f "${FIREHOL_TMP}"	&& rm -f "${FIREHOL_TMP}"
	test -f "${FIREHOL_TMP}.awk"	&& rm -f "${FIREHOL_TMP}.awk"
	
	return 0
}

# Run our exit even if we don't call exit.
trap firehol_exit EXIT



# ------------------------------------------------------------------------------
# Keep track of all interfaces the script uses

register_iface() {
	local iface="${1}"
	
	local found=0
	local x=
	for x in ${work_interfaces}
	do
		if [ "${x}" = "${iface}" ]
		then
			found=1
			break
		fi
	done
	
	test $found -eq 0 && work_interfaces="${work_interfaces} ${iface}"
}


# ------------------------------------------------------------------------------
# Check the status of the current primary command.
# WHY:
# Some sanity check for the order of commands in the configuration file.
# Each function has a "require_work type command" in order to check that it is
# placed in a valid point. This means that if you place a "route" command in an
# interface section (and many other compinations) it will fail.

require_work() {
	local type="${1}"
	local cmd="${2}"
	
	case "${type}" in
		clear)
			test ! -z "${work_cmd}" && error "Previous work was not applied." && return 1
			;;
		
		set)
			test -z "${work_cmd}" && error "The command used requires that a primary command is set." && return 1
			test ! ${work_cmd} = "${cmd}" -a ! "${cmd}" = "any"  && error "Primary command is '${work_cmd}' but '${cmd}' is required." && return 1
			;;
			
		*)
			error "Unknown work status '${type}'."
			return 1
			;;
	esac
	
	return 0
}


# ------------------------------------------------------------------------------
# Finalizes the rules of the last primary command.
# Finalization occures automatically when a new primary command is executed and
# when the script finishes.

close_cmd() {
	case ${work_cmd} in
		interface)
			close_interface
			;;
		
		router)
			close_router
			;;
		
		'')
			;;
		
		*)
			error "Unknown work '${work_cmd}'."
			return 1
			;;
	esac
	
	# Reset the current status variables to empty/default
	work_cmd=
	work_name=
	work_policy=${DEFAULT_INTERFACE_POLICY}
	
	return 0
}

policy() {
	require_work set interface || return 1
	
	work_policy=${1}
	
	return 0
}

# ------------------------------------------------------------------------------
# PRIMARY COMMAND: interface
# Setup rules specific to an interface (physical or logical)

interface() {
	# --- close any open command ---
	
	close_cmd
	
	
	# --- test prerequisites ---
	
	require_work clear || return 1
	
	
	# --- get paramaters and validate them ---
	
	# Get the interface
	local inface=$1; shift
	test -z "${inface}" && error "interface is not set" && return 1
	
	# Get the name for this interface
	local name=$1; shift
	test -z "${name}" && error "Name is not set" && return 1
	
	
	# --- do the job ---
	
	work_cmd="${FUNCNAME}"
	work_name="${name}"
	
	create_chain in_${work_name} INPUT inface ${inface} "$@"
	create_chain out_${work_name} OUTPUT reverse inface ${inface} "$@"
	
	return 0
}

# ------------------------------------------------------------------------------
# close_interface()
# Finalizes the rules for the last interface primary command.

close_interface() {
	require_work set interface || return 1
	
	local inlog=
	local outlog=
	case ${work_policy} in
		return|RETURN)
			return 0
			;;
			
		accept|ACCEPT)
			inlog=
			outlog=
			;;
		
		*)
			inlog="loglimit IN-${work_name}"
			outlog="loglimit OUT-${work_name}"
			;;
	esac
	
	rule chain in_${work_name} ${inlog} action ${work_policy}
	rule reverse chain out_${work_name} ${outlog} action ${work_policy}
	
	return 0
}


router() {
	# --- close any open command ---
	
	close_cmd
	
	
	# --- test prerequisites ---
	
	require_work clear || return 1
	
	
	# --- get paramaters and validate them ---
	
	# Get the name for this router
	local name=$1; shift
	test -z "${name}" && error "router name is not set" && return 1
	
	
	# --- do the job ---
	
	work_cmd="${FUNCNAME}"
	work_name="${name}"
	
	create_chain in_${work_name} FORWARD reverse "$@"
	create_chain out_${work_name} FORWARD "$@"
	
	return 0
}

close_router() {
	require_work set router || return 1

# routers always have RETURN as policy	
#	local inlog=
#	local outlog=
#	case ${work_policy} in
#		return|RETURN)
#			return 0
#			;;
#		
#		accept|ACCEPT)
#			inlog=
#			outlog=
#			;;
#		
#		*)
#			inlog="loglimit PASSIN-${work_name}"
#			outlog="loglimit PASSOUT-${work_name}"
#			;;
#	esac
#	
#	rule chain in_${work_name} ${inlog} action ${work_policy}
#	rule reverse chain out_${work_name} ${outlog} action ${work_policy}
	
	return 0
}

close_master() {
	rule chain INPUT loglimit "IN-unknown" action DROP
	rule chain OUTPUT loglimit "OUT-unknown" action DROP
	rule chain FORWARD loglimit "PASS-unknown" action DROP
	return 0
}


rule() {
	local chain=
	
	local inface=any
	local infacenot=
	
	local outface=any
	local outfacenot=
	
	local src=any
	local srcnot=
	
	local dst=any
	local dstnot=
	
	local sport=any
	local sportnot=
	
	local dport=any
	local dportnot=
	
	local proto=any
	local protonot=
	
	local log=
	local logtxt=
	
	local limit=
	local burst=
	
	local iplimit=
	local iplimit_mask=
	
	local action=
	
	local state=
	local statenot=
	
	local custom=
	
	local failed=0
	local reverse=0
	
	while [ ! -z "$1" ]
	do
		case "$1" in
			reverse|REVERSE)
				reverse=1
				shift
				;;
				
			chain|CHAIN)
				chain="$2"
				shift 2
				;;
				
			inface|INFACE)
				shift
				if [ ${reverse} -eq 0 ]
				then
					infacenot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						infacenot="!"
					fi
					inface="$1"
				else
					outfacenot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						outfacenot="!"
					fi
					outface="$1"
				fi
				shift
				;;
				
			outface|OUTFACE)
				shift
				if [ ${reverse} -eq 0 ]
				then
					outfacenot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						outfacenot="!"
					fi
					outface="$1"
				else
					infacenot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						infacenot="!"
					fi
					inface="$1"
				fi
				shift
				;;
				
			src|SRC|source|SOURCE)
				shift
				if [ ${reverse} -eq 0 ]
				then
					srcnot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						srcnot="!"
					fi
					src="$1"
				else
					dstnot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						dstnot="!"
					fi
					dst="$1"
				fi
				shift
				;;
				
			dst|DST|destination|DESTINATION)
				shift
				if [ ${reverse} -eq 0 ]
				then
					dstnot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						dstnot="!"
					fi
					dst="$1"
				else
					srcnot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						srcnot="!"
					fi
					src="$1"
				fi
				shift
				;;
				
			sport|SPORT|sourceport|SOURCEPORT)
				shift
				if [ ${reverse} -eq 0 ]
				then
					sportnot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						sportnot="!"
					fi
					sport="$1"
				else
					dportnot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						dportnot="!"
					fi
					dport="$1"
				fi
				shift
				;;
				
			dport|DPORT|destinationport|DESTINATIONPORT)
				shift
				if [ ${reverse} -eq 0 ]
				then
					dportnot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						dportnot="!"
					fi
					dport="$1"
				else
					sportnot=
					if [ "$1" = "not" -o "$1" = "NOT" ]
					then
						shift
						sportnot="!"
					fi
					sport="$1"
				fi
				shift
				;;
				
			proto|PROTO|protocol|PROTOCOL)
				shift
				protonot=
				if [ "$1" = "not" -o "$1" = "NOT" ]
				then
					shift
					protonot="!"
				fi
				proto="$1"
				shift
				;;
				
			custom|CUSTOM)
				custom="$2"
				shift 2
				;;
				
			log|LOG)
				log=normal
				logtxt="$2"
				shift 2
				;;
				
			loglimit|LOGLIMIT)
				log=limit
				logtxt="$2"
				shift 2
				;;
				
			limit|LIMIT)
				limit="$2"
				burst="$3"
				shift 3
				;;
				
			iplimit|IPLIMIT)
				iplimit="$2"
				iplimit_mask="$3"
				shift 3
				;;
				
			action|ACTION)
				action="$2"
				shift 2
				;;
				
			state|STATE)
				shift
				statenot=
				if [ "$1" = "not" -o "$1" = "NOT" ]
				then
					shift
					statenot="!"
				fi
				state="$1"
				shift
				;;
				
			*)
				error "Cannot understand directive '$1'."
				return 1
				;;
		esac
	done
	
	
	case ${action} in
		accept|ACCEPT)
			action=ACCEPT
			;;
			
		deny|DENY)
			action=DENY
			;;
			
		reject|REJECT)
			action=REJECT
			;;
			
		drop|DROP)
			action=DROP
			;;
			
		return|RETURN)
			action=RETURN
			;;
			
		none|NONE)
			action=NONE
			;;
	esac
	
	local inf=
	for inf in ${inface}
	do
		local inf_arg=
		
		case ${inf} in
			any|ANY)
				inf_arg=
				;;
			
			*)
				inf_arg="-i ${infacenot} ${inf}"
				register_iface ${inf}
				;;
		esac
		
		local outf=
		for outf in ${outface}
		do
			local outf_arg=
			
			case ${outf} in
				any|ANY)
					outf_arg=
					;;
				
				*)
					outf_arg="-o ${outfacenot} ${outf}"
					register_iface ${outf}
					;;
			esac
			
			local s=
			for s in ${src}
			do
				local s_arg=
				
				case ${s} in
					any|ANY)
						s_arg=
						;;
					
					*)
						s_arg="-s ${srcnot} ${s}"
						;;
				esac
				
				local d=
				for d in ${dst}
				do
					local d_arg=
					
					case ${d} in
						any|ANY)
							d_arg=
							;;
						
						*)
							d_arg="-d ${dstnot} ${d}"
							;;
					esac
					
					local sp=
					for sp in ${sport}
					do
						local sp_arg=
						
						case ${sp} in
							any|ANY)
								sp_arg=
								;;
							
							*)
								sp_arg="--sport ${sportnot} ${sp}"
								;;
						esac
						
						local dp=
						for dp in ${dport}
						do
							local dp_arg=
							
							case ${dp} in
								any|ANY)
									dp_arg=
									;;
								
								*)
									dp_arg="--dport ${dportnot} ${dp}"
									;;
							esac
							
							local pr=
							for pr in ${proto}
							do
								local proto_arg=
								
								case ${pr} in
									any|ANY)
										proto_arg=
										;;
									
									*)
										proto_arg="-p ${protonot} ${proto}"
										;;
								esac
								
								local state_arg=
								if [ ! -z "${state}" ]
								then
									state_arg="-m state ${statenot} --state ${state}"
								else
									state_arg=
								fi
								
								local limit_arg=
								if [ ! -z "${limit}" ]
								then
									limit_arg="-m limit --limit ${limit} --limit-burst ${burst}"
								else
									limit_arg=
								fi
								
								local iplimit_arg=
								if [ ! -z "${iplimit}" ]
								then
									iplimit_arg="-m iplimit --iplimit-above ${iplimit} --iplimit-mask ${iplimit_mask}"
								else
									iplimit_arg=
								fi
								
								local basecmd="-A ${chain} ${inf_arg} ${outf_arg} ${state_arg} ${limit_arg} ${iplimit_arg} ${proto_arg} ${s_arg} ${sp_arg} ${d_arg} ${dp_arg} ${custom}"
								
								case "${log}" in
									'')
										;;
									
									limit)
										iptables ${basecmd} -m limit --limit 1/second -j LOG --log-prefix="\"${logtxt}:\""
										;;
								
									normal)
										iptables ${basecmd} -j LOG --log-prefix="\"${logtxt}:\""
										;;
										
									*)
										error "Unknown log value '${log}'."
										;;
								esac
								
								if [ ! ${action} = NONE ]
								then
									iptables ${basecmd} -j ${action}
									test $? -gt 0 && failed=$[failed + 1]
								fi
							done
						done
					done
				done
			done
		done
	done
	
	test ${failed} -gt 0 && error "There are ${failed} failed commands." && return 1
	return 0
}

postprocess() {
	local tmp=" >${FIREHOL_OUTPUT}.log 2>&1"
	test ${FIREHOL_DEBUG} -eq 1 && local tmp=
	
	echo "$@" " $tmp # L:${FIREHOL_LINEID}" >>${FIREHOL_OUTPUT}
	
	test ${FIREHOL_DEBUG} -eq 0 && echo "check_final_status \$? '" "$@" "' ${FIREHOL_LINEID}" >>${FIREHOL_OUTPUT}
	
	return 0
}

iptables() {
	postprocess "/sbin/iptables" "$@"
	
	return 0
}

check_final_status() {
	if [ $1 -gt 0 ]
	then
		work_final_status=$[work_final_status + 1]
		echo >&2
		echo >&2 "--------------------------------------------------------------------------------"
		echo >&2 "ERROR #: ${work_final_status}."
		echo >&2 "WHAT   : A runtime command failed to execute."
		echo >&2 "SOURCE : line ${3} of ${FIREHOL_CONFIG}"
		echo >&2 "COMMAND: ${2}"
		echo >&2 "OUTPUT : (of the failed command)"
		cat ${FIREHOL_OUTPUT}.log
		echo >&2
	fi
	
	return 0
}

create_chain() {
	local newchain="${1}"
	local oldchain="${2}"
	shift 2
	
#	echo >&2 "CREATED CHAINS : ${work_created_chains}"
#	echo >&2 "REQUESTED CHAIN: ${newchain}"
	
	local x=
	for x in ${work_created_chains}
	do
		test "${x}" = "${newchain}" && return 1
	done
	
	iptables -N "${newchain}" || return 1
	rule chain "${oldchain}" action "${newchain}" "$@" || return 1
	
	work_created_chains="${work_created_chains} ${newchain}"
	
	return 0
}

error() {
	echo >&2
	echo >&2 "*** Error in file: ${FIREHOL_CONFIG}, line ${FIREHOL_LINEID}:"
	echo >&2 "$@"
	work_error=1
	
	return 0
}

smart_function() {
	local type="${1}"	# The current subcommand: server/client/route
	local services="${2}"	# The services to implement
	shift 2
	
	local service=
	for service in $services
	do
		# Try the simple services first
		simple_service "${type}" "${service}" "$@"
		test $? -eq 0 && continue
		
		# Try the custom services
		local fn="rules_${service}"
		"${fn}" "${type}" "$@"
		if [ $? -gt 0 ]
		then
			error "Function ${fn} returned an error."
			return 1
		fi
	done
	
	return 0
}

server() {
	require_work set interface || return 1
	smart_function server "$@"
	return $?
}

client() {
	require_work set interface || return 1
	smart_function client "$@"
	return $?
}

route() {
	require_work set router || return 1
	smart_function route "$@"
	return $?
}


simple_service() {
	local type="${1}"; shift
	local server="${1}"; shift
	
	local server_varname="server_${server}_ports"
	local server_ports="`eval echo \\\$${server_varname}`"
	
	local client_varname="client_${server}_ports"
	local client_ports="`eval echo \\\$${client_varname}`"
	
	test -z "${server_ports}" -o -z "${client_ports}" && return 1
	
	rules_custom "${type}" "${server}" "${server_ports}" "${client_ports}" "$@"
	return $?
}


rules_custom() {
	local type="${1}"; shift
	
	local server="${1}"; shift
	local my_server_ports="${1}"; shift
	local my_client_ports="${1}"; shift
	
	local mychain="${work_name}_${server}_${type}"
	
	create_chain in_${mychain} in_${work_name}
	create_chain out_${mychain} out_${work_name}
	
	local in=in
	local out=out
	if [ "${type}" = "route" -o "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	local sp=
	for sp in ${my_server_ports}
	do
		local proto="`echo $sp | cut -d '/' -f 1`"
		local sport="`echo $sp | cut -d '/' -f 2`"
		
		local cp=
		for cp in ${my_client_ports}
		do
			local cport=
			case ${cp} in
				default)
					cport="${client_ports}"
					;;
					
				*)	cport="${cp}"
					;;
			esac
			
			# allow new and established incoming packets
			rule action "$@" chain ${in}_${mychain} proto ${proto} sport ${cport} dport ${sport} state NEW,ESTABLISHED || return 1
			
			# allow outgoing established packets
			rule reverse action "$@" chain ${out}_${mychain} proto ${proto} sport ${cport} dport ${sport} state ESTABLISHED || return 1
		done
	done
	
	return 0
}


# --- protection ---------------------------------------------------------------

protection() {
	local type="${1}"
	local rate="${2}"
	local burst="${3}"
	
	require_work set interface || return 1
	
	test -z "${rate}"  && rate="100/s"
	test -z "${burst}" && burst="4"
	
	local x=
	for x in ${type}
	do
		case ${x} in
			none|NONE)
				return 0
				;;
			
			strong|STRONG|full|FULL|all|ALL)
				protection "fragments new-tcp-w/o-syn syn-floods malformed-xmas malformed-null" "${rate}" "${burst}"
				return $?
				;;
				
			fragments|FRAGMENTS)
				local mychain="pr_${work_name}_fragments"
				create_chain ${mychain} in_${work_name} custom "-f"
				
				rule chain ${mychain} loglimit "PACKET FRAGMENTS" action drop 
				;;
				
			new-tcp-w/o-syn|NEW-TCP-W/O-SYN)
				local mychain="pr_${work_name}_nosyn"
				create_chain ${mychain} in_${work_name} proto tcp state NEW custom "! --syn"
				
				rule chain ${mychain} loglimit "NEW TCP w/o SYN" action drop
				;;
				
			syn-floods|SYN-FLOODS)
				local mychain="pr_${work_name}_synflood"
				create_chain ${mychain} in_${work_name} proto tcp custom "--syn"
				
				rule chain ${mychain} limit "${rate}" "${burst}" action return
				rule chain ${mychain} loglimit "SYN FLOOD" action drop
				;;
				
			malformed-xmas|MALFORMED-XMAS)
				local mychain="pr_${work_name}_malxmas"
				create_chain ${mychain} in_${work_name} proto tcp custom "--tcp-flags ALL ALL"
				
				rule chain ${mychain} loglimit "MALFORMED XMAS" action drop
				;;
				
			malformed-null|MALFORMED-NULL)
				local mychain="pr_${work_name}_malnull"
				create_chain ${mychain} in_${work_name} proto tcp custom "--tcp-flags ALL NONE"
				
				rule chain ${mychain} loglimit "MALFORMED NULL" action drop
				;;
		esac
	done
	
	return 0
}

# --- set_proc_value -----------------------------------------------------------

set_proc_value() {
	local file="${1}"
	local value="${2}"
	local why="${3}"
	
	if [ ! -f "${file}" ]
	then
		echo >&2 "WARNING: File '${file}' does not exist."
		return 1
	fi
	
	local t="`cat ${1}`"
	if [ ! "$t" = "${value}" ]
	then
		local name=`echo ${file} | tr '/' '.' | cut -d '.' -f 4-`
		echo >&2 "WARNING: To ${why}, you should run:"
		echo >&2 "         \"sysctl -w ${name}=${value}\""
		echo >&2
#		postprocess "echo 1 >'${file}'"
	fi
}


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# MAIN PROCESSING
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------

echo -n $"FireHOL: Setting firewall defaults:"
ret=0

# --- Initialization -----------------------------------------------------------

modprobe ip_tables			|| ret=$[ret + 1]
modprobe ip_conntrack			|| ret=$[ret + 1]
modprobe ip_conntrack_ftp		|| ret=$[ret + 1]


# ------------------------------------------------------------------------------

# Ignore all pings
###set_proc_value /proc/sys/net/ipv4/icmp_echo_ignore_all 1 "ignore all pings"

# Ignore all icmp broadcasts - protects from smurfing
###set_proc_value /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts 1 "be protected from smurfing"

# Ignore source routing
###set_proc_value /proc/sys/net/ipv4/conf/all/accept_source_route 0 "ignore source routing"

# Ignore routing redirects
###set_proc_value /proc/sys/net/ipv4/conf/all/accept_redirects 0 "ignore redirects"

# Enable bad error message protection.
###set_proc_value /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses 1 "be protected from bad error messages"

# Turn on reverse path filtering. This helps make sure that packets use
# legitimate source addresses, by automatically rejecting incoming packets
# if the routing table entry for their source address doesn't match the network
# interface they're arriving on. This has security advantages because it prevents
# so-called IP spoofing, however it can pose problems if you use asymmetric routing
# (packets from you to a host take a different path than packets from that host to you)
# or if you operate a non-routing host which has several IP addresses on different
# interfaces. (Note - If you turn on IP forwarding, you will also get this).
###set_proc_value /proc/sys/net/ipv4/conf/all/rp_filter 1 "match routing table with source interfaces"

# Log spoofed packets, source routed packets, redirect packets.
###set_proc_value /proc/sys/net/ipv4/conf/all/log_martians 1 "log spoofing, source routing, redirects"

# ------------------------------------------------------------------------------

iptables -F				|| ret=$[ret + 1]
iptables -X				|| ret=$[ret + 1]
iptables -Z				|| ret=$[ret + 1]
iptables -t nat -F			|| ret=$[ret + 1]
iptables -t nat -X			|| ret=$[ret + 1]
iptables -t nat -Z			|| ret=$[ret + 1]
iptables -t mangle -F			|| ret=$[ret + 1]
iptables -t mangle -X			|| ret=$[ret + 1]
iptables -t mangle -Z			|| ret=$[ret + 1]


# ------------------------------------------------------------------------------
# Set everything to accept in order not to loose the connection the user might
# be working now.

iptables -P INPUT ACCEPT		|| ret=$[ret + 1]
iptables -P OUTPUT ACCEPT		|| ret=$[ret + 1]
iptables -P FORWARD ACCEPT		|| ret=$[ret + 1]


# ------------------------------------------------------------------------------
# Accept everything in/out the loopback device.

iptables -A INPUT -i lo -j ACCEPT	|| ret=$[ret + 1]
iptables -A OUTPUT -o lo -j ACCEPT	|| ret=$[ret + 1]

if [ $ret -eq 0 ]
then
	success $"FireHOL: Setting firewall defaults:"
	echo
else
	failure$ $"FireHOL: Setting firewall defaults:"
	echo
	exit 1
fi


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

echo -n $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
ret=0

# ------------------------------------------------------------------------------
# Create a small awk script that inserts line numbers in the configuration file
# just before each known directive.
# These line numbers will be used for debugging the configuration script.

cat >"${FIREHOL_TMP}.awk" <<"EOF"
/^[[:space:]]*interface[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*router[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*route[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*client[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*server[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*iptables[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
{ print }
EOF

cat ${FIREHOL_CONFIG} | awk -f "${FIREHOL_TMP}.awk" >${FIREHOL_TMP}
rm -f "${FIREHOL_TMP}.awk"

# ------------------------------------------------------------------------------
# Run the configuration file.

enable -n trap			# Disable the trap buildin shell command.
enable -n exit			# Disable the exit buildin shell command.
source ${FIREHOL_TMP} "$@"	# Run the configuration as a normal script.
FIREHOL_LINEID="FIN"
enable trap			# Enable the trap buildin shell command.
enable exit			# Enable the exit buildin shell command.


# ------------------------------------------------------------------------------
# Make sure the script stated a version number.

if [ ${FIREHOL_VERSION_CHECKED} -eq 0 ]
then
	error "The configuration file does not state a version number."
	failure $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
	echo
	exit 1
fi

close_cmd					|| ret=$[ret + 1]
close_master					|| ret=$[ret + 1]

iptables -P INPUT ${DEFAULT_INTERFACE_POLICY}	|| ret=$[ret + 1]
iptables -P OUTPUT ${DEFAULT_INTERFACE_POLICY}	|| ret=$[ret + 1]
iptables -P FORWARD ${DEFAULT_INTERFACE_POLICY}	|| ret=$[ret + 1]

iptables -t nat -P PREROUTING ACCEPT		|| ret=$[ret + 1]
iptables -t nat -P POSTROUTING ACCEPT		|| ret=$[ret + 1]
iptables -t nat -P OUTPUT ACCEPT		|| ret=$[ret + 1]

iptables -t mangle -P PREROUTING ACCEPT		|| ret=$[ret + 1]
#iptables -t mangle -P POSTROUTING ACCEPT	|| ret=$[ret + 1]
iptables -t mangle -P OUTPUT ACCEPT		|| ret=$[ret + 1]

if [ ${work_error} -gt 0 -o $ret -gt 0 ]
then
	echo >&2
	echo >&2 "NOTICE: No changes made to your firewall."
	failure $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
	echo
	exit 1
fi

success $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
echo


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

if [ ${FIREHOL_DEBUG} -eq 1 ]
then
	cat ${FIREHOL_OUTPUT}
	exit 1
fi


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

echo -n $"FireHOL: Saving your old firewall to a temporary file:"
iptables-save >${FIREHOL_SAVED}
if [ $? -eq 0 ]
then
	success $"FireHOL: Saving your old firewall to a temporary file:"
	echo
else
	failure $"FireHOL: Saving your old firewall to a temporary file:"
	echo
	exit 1
fi


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

echo -n $"FireHOL: Activating new firewall:"

source ${FIREHOL_OUTPUT} "$@"

if [ ${work_final_status} -gt 0 ]
then
	failure $"FireHOL: Activating new firewall:"
	echo
	
	echo -n "FireHOL: Restoring old firewall:"
	iptables-restore <${FIREHOL_SAVED}
	if [ $? -eq 0 ]
	then
		success "FireHOL: Restoring old firewall:"
	else
		failure "FireHOL: Restoring old firewall:"
	fi
	echo
	exit 1
fi
success $"FireHOL: Activating new firewall:"
echo
touch /var/lock/subsys/iptables

# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

if [ ${FIREHOL_SAVE} -eq 1 ]
then
	/etc/init.d/iptables save
	exit $?
fi
