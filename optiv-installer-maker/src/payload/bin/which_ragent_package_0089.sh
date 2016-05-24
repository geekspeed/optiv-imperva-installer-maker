#!/bin/sh

RA_KABI_NAME=kabi
KABI_FILE=${RA_KABI_NAME}.txt

RA_PKG_NAME=packages
PKG_FILE=${RA_PKG_NAME}.txt

OS_NAME_=""
OS_MAJOR_VER_=""
PROCESSOR_=""
KERNEL_=""
SP_=""

# This function finds the kernel range from the kabi file (used for UEK only)
# like test X -le Y, only where X and Y are kernel versions
kversion_le()
{
    X=$1
    Y=$2
    
    if [ $X = $Y ]; then
        return 0
    fi
    
    i=1
    for X_VAL in `echo $X | tr - ' '`; do # separate X to values by dashes, e.g. "2.6.5-0.31.0" -> "2.6.5 0.31.0" and iterate the result
        Y_VAL=`echo $Y | cut -d- -f${i}` # take the Y value respective to the current X value
        if [ $X_VAL != $Y_VAL ]; then
            j=1
            for X_VAL_FRAG in `echo $X_VAL | tr . ' '`; do # separate X_VAL to fragments by dots, e.g. "2.6.5" -> "2 6 5" and iterate the result
                Y_VAL_FRAG=`echo $Y_VAL | cut -d. -f${j}` # take the Y_VAL fragment respective to the current X_VAL fragemnt
                if [ -z "$Y_VAL_FRAG" ]; then # corner case: X_VAL has more dots than Y_VAL (e.g. x=2.6.16.60, y=2.6.16)
                    return 1
                fi
                if [ $X_VAL_FRAG != $Y_VAL_FRAG ]; then
                    if [ $X_VAL_FRAG -le $Y_VAL_FRAG ]; then
                        return 0
                    else
                        return 1
                    fi
                fi
                ((j++))
            done
            Y_VAL_FRAG=`echo $Y_VAL | cut -d. -f${j}` # corner case: Y_VAL has more dots than X_VAL. here, j is 1 more than the number of dots in X_VAL.
            if [ -n "$Y_VAL_FRAG" ]; then
                return 0
            fi
        fi
        ((i++))
    done
    return 0 # all X parts are equal to all Y parts
}

find_relevant_kernel_from_kabi()
{
	KERNEL_V=$1
	KERNEL_FLAVOR=$2
	
	cat ${KABI_FILE} | grep "^$KERNEL_FLAVOR" | {
	while read LINE; 
	do
		MIN_KERNEL_PATCH=`echo $LINE | awk '{ print $3 }'`
		MAX_KERNEL_PATCH=`echo $LINE | awk '{ print $4 }'`    
		if [ -z "$MIN_KERNEL_PATCH" -o -z "$MAX_KERNEL_PATCH" ]; then
			return 1
		fi
		
		if kversion_le "$MIN_KERNEL_PATCH" "$KERNEL_V" && kversion_le "$KERNEL_V" "$MAX_KERNEL_PATCH"; then
		    if [ $KERNEL_FLAVOR = TD ]; then
			    echo $LINE | awk '{ print $5 }'
                return 0
			else
			    OEL_DISTRO=`echo $LINE | awk '{ print $5 }'`
				uname -r | grep $OEL_DISTRO >/dev/null # verify the OEL version is the same as shown in the kabi
				if [ $? -eq 0 ]; then
                    echo $LINE | awk '{ print $6 }'
                    return 0
				fi
			fi
		fi
	done
	return 2
	}
}

# For Linux only
get_linux_kernel_patch_level()
{
	SYS_KERNEL_CPUNUM=`cat /boot/config-$(uname -r) 2>/dev/null | grep CONFIG_NR_CPUS | sed 's:.*=::' | xargs`
    SYS_KERNEL_VERSION_STRING=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*\).*:\1:'`
    VER_A=`echo ${SYS_KERNEL_VERSION_STRING} | sed 's:\..*::'`
    VER_B=`echo ${SYS_KERNEL_VERSION_STRING} | sed 's:[0-9]\.*::' | sed 's:\..*::'`
    VER_C=`echo ${SYS_KERNEL_VERSION_STRING} | sed 's:[0-9]\.[0-9]*::' | sed 's:\.*::'`
    #KERNEL_PATCH_LEVEL=`($((${VER_A} << 16)) + $((${VER_B} << 8)) + ${VER_C})`
    KERNEL_PATCH_LEVEL=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*\).*:\1:' | sed 's:\.::g'`
    KERNEL_MAJOR_VER=`uname -r | sed 's:\([0-9]*.[0-9]*.\).*:\1:' | sed 's:\.::g'`
    SMP_KERNEL=`uname -v | awk '{print $2}' | grep -i smp >& /dev/null && echo "true"`
    SMP_STRING=`[ "${SMP_KERNEL}" == "true" ] && echo "SMP"`
    #LINUX_26_CODE=132608
    #LINUX_2616_CODE=132624
    LINUX_26_CODE=26
    LINUX_2616_CODE=2616
    LINUX_2632_CODE=2632

    if [ "${SYS_PLATFORM}" == "i386" ]; then
        if [ "${KERNEL_MAJOR_VER}" -ge  "${LINUX_26_CODE}" ]; then
            # kernel 2.6.9 - hugemem kernel base symbol startes at 02XXXX
            IS_HUGE=`head -n 1 /proc/kallsyms|awk '{print $1}' | grep '^02' >& /dev/null && echo "true"`
            if [ "${IS_HUGE}" != "true" ]; then
                # kernel 2.6.16+ - check config file
                if [ "${KERNEL_PATCH_LEVEL}" -ge  "${LINUX_2616_CODE}" ]; then
					UNAMER=`uname -r`
                    IS_HUGE=`grep "CONFIG_X86_PAE=y" /boot/config-${UNAMER} >& /dev/null && echo "true"`
                fi
            fi
        else
            IS_HUGE=`head -n 1 /proc/ksyms | awk '{print $1}' | grep '^02' >& /dev/null && echo "true"`
            if [ "${IS_HUGE}" != "true" ]; then
                IS_HUGE=`grep "CONFIG_X86_4G=y" /boot/config-$(uname -r) >& /dev/null && echo "true"`
            fi
        fi
	fi

    # normally, we would test RHEL4 rather than kernel v2.6.9, however the latter has proved to be working for a long time and is threfore more trustworthy.
    if [ "${SYS_PLATFORM}" = "x86_64" ] && [ "${SMP_KERNEL}" = "true" ] && [ "${SYS_KERNEL_VERSION_STRING}" = 2.6.9 ] && [ -n "${SYS_KERNEL_CPUNUM}" ] && [ "${SYS_KERNEL_CPUNUM}" -gt 8 ]; then
        SMP_STRING="LARGESMP"
    fi 

    # The test will fail on 2.6.16+ when we have less the 4GB memory and the kernel name has no 'hugemem|pte'
    if [ "${IS_HUGE}" == "true" ]; then
        if [ "${KERNEL_PATCH_LEVEL}" -ge "${LINUX_2616_CODE}" ] && [ "${KERNEL_PATCH_LEVEL}" -lt "${LINUX_2632_CODE}" ]; then
            SMP_STRING="PAE"
        #In RHEL6 and above, the default kernel is PAE, but it is written as SMP in "uname -a"
        elif [ "${KERNEL_PATCH_LEVEL}" -ge "${LINUX_2632_CODE}" ]; then
            SMP_STRING="SMP"
        else
            SMP_STRING="HUGEMEM"
        fi
    fi
    SYS_KERNEL_PATCH_LEVEL=${KERNEL_PATCH_LEVEL}
    SYS_KERNEL_CONFIG=${SMP_STRING}${HUGEMEM_STRING}
    SYS_KERNEL_CONFIG=${SYS_KERNEL_CONFIG:-plain}
}

get_kernel_version()
{
    if [ $1 = UEK ]; then
		echo `uname -r | sed s/.el.*$//g`
	else # $1=TD
	    echo `uname -r | sed s/.TDC.*$//g`
	fi
}

is_uek()
{
    LINUX_2632100_CODE=2632100
	LINUX_381316_CODE=381316
	KERENL_V_SUPPORT_UEK=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*-[0-9]*\).*:\1:' | sed 's:\.::g' | sed 's:\-::g'`
    KERENL_V_CONTAIN_UEK=`uname -r | grep uek`
	IS_OO=`uname -r | awk -F '[-.]' '{print $4}' | rev | cut -c -2 | rev` > /dev/null 2>&1
	IS_NOT_0=`uname -r | awk -F '[-.]' '{print $4}' | rev | cut -c 3- | rev` > /dev/null 2>&1
    
    first_num=`echo $KERENL_V_SUPPORT_UEK | cut -b1`
    second_num=`echo $KERENL_V_SUPPORT_UEK | cut -b2`
    third_num=`echo $KERENL_V_SUPPORT_UEK | cut -b3`
    forth_num=`echo $KERENL_V_SUPPORT_UEK | cut -b4`
    
    EL=none
    uname -r | grep el5 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        EL=el5
    fi
    
	rpm -q kernel-uek > /dev/null 2>&1 # UEK machine - has kernel-uek rpm installed and currently running kernel 2.6.32-100 and higher, and the last 3 digits in the kernel version is of type x00 (x!=0)
	if [ $? -eq 0 ]; then
	    if [ "${SYS_PLATFORM}" = "x86_64" ]; then
            if [ $first_num -eq 2 ] && [ $second_num -eq 6 ] && [ $third_num -eq 3 ] && [ $forth_num -eq 2 ] && [ "${IS_OO}" -eq "00" ] && [ "${IS_NOT_0}" -ne "0" ]; then
		        return 0
            elif [ $first_num -eq 2 ] && [ $second_num -eq 6 ] && [ $third_num -eq 3 ] && [ $forth_num -eq 9 ] && [ "${IS_OO}" -eq "00" ] && [ "${IS_NOT_0}" -ne "0" ]; then
                return 0
            fi
        fi
	fi
	
	# In OEL5, if the kernel patch level is 2.6.32-100 and the platform is x86_64, the machine UEK.
	if [ ${EL} = el5 ] && [ "${SYS_PLATFORM}" = "x86_64" ] && [ "${KERENL_V_SUPPORT_UEK}" -eq "${LINUX_2632100_CODE}" ]; then
	    return 0
    # OELx-UEK3 or higher -> validate that the uname contains the word 'uek'.
	elif [ "${SYS_PLATFORM}" = "x86_64" ] && [ "${KERENL_V_SUPPORT_UEK}" -ge "${LINUX_381316_CODE}" ] && [ ! -z ${KERENL_V_CONTAIN_UEK} ]; then
        return 0
    else # the machine is not UEK
	    return 1
	fi
}

is_xen()
{
    uname -r | grep xen > /dev/null 2>&1
}

is_suse()
{
	if [ -f /etc/SuSE-release ]; then
		SYS_DISTRO_VERSION=`grep VERSION /etc/SuSE-release | awk '{ print $3 }'`
		SYS_DISTRO_SP=`grep PATCHLEVEL /etc/SuSE-release | awk '{ print $3 }'`
		if [ -z "${SYS_DISTRO_SP}" ]; then
			SYS_DISTRO_SP=0
		fi
        
        # Handle cases in which SUSE 11 is represented as SP3, while it is actually SP2
        # Relevant for kernels which start with: 3.0.80-0.5, 3.0.80-0.7, 3.0.93-0.5, 3.0.101-0.5, 3.0.101-0.7
        # Taken from https://wiki.novell.com/index.php/Kernel_versions
        if [ $SYS_DISTRO_VERSION = 11 ] && [ $SYS_DISTRO_SP = 3 ]; then
            SUSE_KERNEL_VERSION_DIGIT_1=`uname -r | awk -F "[.-]" '{print $1}'`
            SUSE_KERNEL_VERSION_DIGIT_2=`uname -r | awk -F "[.-]" '{print $2}'`
            SUSE_KERNEL_VERSION_DIGIT_3=`uname -r | awk -F "[.-]" '{print $3}'`
            SUSE_KERNEL_VERSION_DIGIT_4=`uname -r | awk -F "[.-]" '{print $4}'`
            SUSE_KERNEL_VERSION_DIGIT_5=`uname -r | awk -F "[.-]" '{print $5}'`
            if [ $SUSE_KERNEL_VERSION_DIGIT_1 = 3 ] && [ $SUSE_KERNEL_VERSION_DIGIT_2 = 0 ] && [ $SUSE_KERNEL_VERSION_DIGIT_4 = 0 ]; then
                if [ $SUSE_KERNEL_VERSION_DIGIT_3 = 80 ] || [ $SUSE_KERNEL_VERSION_DIGIT_3 = 101 ]; then
                    if [ $SUSE_KERNEL_VERSION_DIGIT_5 = 5 ] || [ $SUSE_KERNEL_VERSION_DIGIT_5 = 7 ]; then
                        SYS_DISTRO_SP=2
                    fi
                elif [ $SUSE_KERNEL_VERSION_DIGIT_3 = 93 ]; then
                    if [ $SUSE_KERNEL_VERSION_DIGIT_5 = 5 ]; then
                        SYS_DISTRO_SP=2
                    fi
                fi
            fi
        fi
		return 0
	else
		return 1
	fi
}

is_td()
{
    is_suse
	if [ $? -eq 0 ]; then
	    uname -r | grep TDC >/dev/null 2>&1
		if [ $? -eq 0 ]; then
		    return 0
		else
		    return 1
	    fi
    else
        return 1		
	fi
}

is_rhel()
{
    # First of all check if lsb_release command available and grab the major and minor version of the OS
    command -v lsb_release >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        SYS_DISTRO_VERSION=`lsb_release -a | grep Release | awk '{print $2}' | grep -o "[0-9]" | head -n 1`
        SYS_DISTRO_MINOR_VERSION=`lsb_release -a | grep Release | awk '{print $2}' | grep -o "[0-9]" | tail -n 1`
    fi
    
    # In case the output of lsb_release was empty, take the output from /etc/redhat-release
    if [ -z $SYS_DISTRO_VERSION ] && [ -f /etc/redhat-release ]; then
		SYS_DISTRO_VERSION=`grep -o "[0-9]" /etc/redhat-release | head -n 1`
        SYS_DISTRO_MINOR_VERSION=`grep -o "[0-9]" /etc/redhat-release | tail -n 1`
        if [ -z "${SYS_DISTRO_MINOR_VERSION}" ]; then
            SYS_DISTRO_MINOR_VERSION=0
        fi
	fi
    
    if [ -z "$SYS_DISTRO_VERSION" ]; then
        return 1
    else
        return 0
    fi
}

get_linux_rhel_6_KABI ()
{
    # Find the relevant RHEL6 Kernel ABI
    SYS_KERNEL_VERSION=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*\).*:\1:' | sed 's:\.::g'`
	LINUX_2632_CODE=2632
    if [ "${SYS_KERNEL_VERSION}" -eq "${LINUX_2632_CODE}" ]; then
	    RHEL_6K1_CODE=2632431
		RHEL_6_KABI_V=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*-[0-9]*\).*:\1:' | sed 's:\.::g' | sed 's:\-::g'`
		RHEL_6K0_DISTRO_VER=6K0
		RHEL_6K1_DISTRO_VER=6K1
		
		if [ $RHEL_6_KABI_V -ge $RHEL_6K1_CODE ]; then # if Kernel ABI >= 2632431 (rhel6 update 5)
		    SYS_DISTRO_VERSION=${RHEL_6K1_DISTRO_VER}
		else # if Kernel ABI < 2632431
		    SYS_DISTRO_VERSION=${RHEL_6K0_DISTRO_VER}
		fi
    fi
	return 0
}

get_sys_os()
{
    SYS_OS=`uname -s | sed 's:[^A-Za-z0-9]*::g'`
	if [ -z "${SYS_OS}" ]; then
	    echo "Could not retrieve OS information."
		if [ $GET_OS_DETAILS = true ]; then
	        exit 1
		else
		    out 1
		fi
    else
	    if [ "${SYS_OS}" != AIX ]; then
		    SYS_PLATFORM=`uname -i`
		    if [ -z "${SYS_PLATFORM}" ]; then
			    echo "Could not retrieve OS information."
				if [ $GET_OS_DETAILS = true ]; then
			        exit 1
				else
				    out 1
		        fi
		    fi
	    fi
	fi
}

init_linux_vars_from_kabi()
{
    KERNEL_V=`get_kernel_version $1`
	KERNEL_FLAVOR_V=`find_relevant_kernel_from_kabi ${KERNEL_V} $1`
	RC=$?
	if [ $RC != 0 ]; then
		if [ $RC == 1 ]; then
			echo "kabi.txt text file is corrupted."
		elif [ $RC == 2 ]; then
			echo "Could not find relevant package for $1 $KERNEL_V"
		fi
		if [ $GET_OS_DETAILS = true ]; then
		    exit 1
		else
		    out 1
		fi
	fi
}

check_solaris_11_1_patch ()
{
    # Minimal Solaris 11.1 branch level is: 0.175.1.15.0.4.0
    solaris_11_1_branch=`pkg info entire | grep Branch | awk -F":  " '{print $2}' | sed 's/ //g'`
	# Remove spaces if there are any
    # We will check only the first 4 numbers, becasue there is no need to be more specific
    first_num=`echo $solaris_11_1_branch | cut -d . -f1`
    second_num=`echo $solaris_11_1_branch | cut -d . -f2`
    third_num=`echo $solaris_11_1_branch | cut -d . -f3`
    forth_num=`echo $solaris_11_1_branch | cut -d . -f4`
    
    if [ $first_num -ge 1 ]; then
        return 0
    fi
    
	RC=0
    if [ $second_num -lt 175 ]; then
        RC=1
    fi
	
	if [ $second_num -eq 175 ] && [ $third_num -lt 1 ]; then
	    RC=1
	fi
	
	if [ $second_num -eq 175 ] && [ $third_num -eq 1 ] && [ $forth_num -lt 15 ]; then
        RC=1
    fi
	
	if [ $RC = 1 ]; then
        return 1
	else
	    return 0
	fi
}

init_linux_xen_vars()
{
    is_rhel
    get_linux_kernel_patch_level
    SYS_OS=RHEL
	SYS_KERNEL=XEN
}

init_linux_uek_vars()
{
    is_rhel
	init_linux_vars_from_kabi UEK
	SYS_OS=OEL
	SYS_KERNEL=${KERNEL_FLAVOR_V}   
}

init_linux_suse_vars()
{
    get_linux_kernel_patch_level
	SYS_OS=SLE
	SYS_KERNEL=${SYS_KERNEL_CONFIG}
}

init_linux_td_vars()
{
    init_linux_vars_from_kabi TD
	SYS_OS=TD-SLE
	SYS_KERNEL=${KERNEL_FLAVOR_V}
}

init_linux_rhel_vars()
{
    PACKAGE_VERSION=$1
	get_linux_kernel_patch_level
	
	# We support RHEL 6 K0/K1 in 9.5.0 and 11.0.1 and not 6 like in newer versions
    if [ ${SYS_DISTRO_VERSION} = 6 ]; then
	    if [ "${PACKAGE_VERSION}" = "9.5.0" ]; then
	        get_linux_rhel_6_KABI
	    fi
    fi
	SYS_OS=RHEL
	SYS_KERNEL=${SMP_STRING}
}

init_sunos_vars()
{
	if [ "${SYS_PLATFORM}" = "i86pc" ]; then
		ISALIST=`isalist | sed 's: .*::' | xargs`
		if [ "${ISALIST}" = "amd64" ]; then
			SYS_PLATFORM=x86_64
		else
			SYS_PLATFORM=x86
		fi
	else
		SYS_PLATFORM=`isainfo -n`
	fi
	SYS_DISTRO_VERSION=`uname -r`
    
    if [ "`uname -v`" = "11.1" ]; then
        check_solaris_11_1_patch
        if [ $? -eq 1 ]; then
            SYS_DISTRO_VERSION=dummy
        fi
    fi
}

init_hpux_vars()
{
    SYS_PLATFORM=`uname -m`
	if [ "${SYS_PLATFORM}" != "ia64" ]; then
		SYS_PLATFORM=hppa
	fi
	SYS_DISTRO_VERSION=`uname -r | awk -F. '{print $2"."$3}'`
}

init_aix_vars()
{
    SYS_V=`uname -v`
	SYS_R=`uname -r`
	SYS_DISTRO_VERSION=${SYS_V}${SYS_R}
	SYS_P=`uname -p`
	SYS_B=`bootinfo -K`
	SYS_PLATFORM=${SYS_P}${SYS_B}  
}

GET_OS_DETAILS=false

init_get_os_details_vars()
{
    GET_OS_DETAILS=true
    KABI_FILE="${AGENT_HOME}"/bin/kernel/kabi.txt
	get_sys_os
	if  [ "${SYS_OS}" = "Linux" ]; then
        if is_xen; then
		    init_linux_xen_vars
		elif is_uek; then
		    init_linux_uek_vars
		elif is_td; then
            init_linux_td_vars
		elif is_suse; then
		    init_linux_suse_vars
		elif is_rhel; then
		    init_linux_rhel_vars
		else
		    echo "Unsupported Linux distribution"
		    exit 1
		fi
    elif [ "${SYS_OS}" = "SunOS" ]; then
		init_sunos_vars
    elif [ "${SYS_OS}" = "HPUX" ]; then
		init_hpux_vars
    elif [ "${SYS_OS}" = "AIX" ]; then
		init_aix_vars
	else
	    echo "Unsupported OS"
	    exit 1
	fi
	
	OS_NAME_=${SYS_OS}
	OS_MAJOR_VER_=`echo ${SYS_DISTRO_VERSION}`
	PROCESSOR_=${SYS_PLATFORM}
	KERNEL_=${SYS_KERNEL}
	SP_=${SYS_DISTRO_SP}
}

extract_files()
{
	ARCHIVE1=`awk '/^__ARCHIVE1__/ {print NR + 1; exit 0; }' $0`
	ARCHIVE2=`awk '/^__ARCHIVE2__/ {print NR + 1; exit 0; }' $0`
	PKG_ROWS=`expr $ARCHIVE2 - $ARCHIVE1 - 1`
	if [ `uname -s` != "SunOS" ]; then
		TAIL_FLAG="-n"
	fi
	tail ${TAIL_FLAG} +$ARCHIVE1 $0 | head -n $PKG_ROWS > $PKG_FILE
	tail ${TAIL_FLAG} +$ARCHIVE2 $0 > $KABI_FILE
}

usage ()
{
    echo "Usage: which_ragent_package -v <ragent version>"
    cat "${PKG_FILE}" | echo "Available versions are: `grep RELEASE | grep -v 'grep' | awk '{print $2}' | tr '\n' '\ '`"
    echo "Example: which_ragent_package -v 11.5.0"
    echo "*** Please verify that you run the latest version of which_ragent_package available at https://ftp-us.imperva.com ***"
}

out()
{
	rm -rf ${KABI_FILE}
	rm -rf ${PKG_FILE}
	exit $1
}

check_version_input()
{
    # Validate input is x.y using regex
    INPUT=`echo "$1" | sed -e 's/[0-9]*\.[0-9]\.[0-9]//'`
    if [ ! -z "$INPUT" ]; then
        return 1
    fi
    X=`grep "RELEASE $1" ${PKG_FILE}`
    return $?
}

print_pkg_name()
{
	OS_STR=$1
	OS_VER=$2
	PLATFORM=$3
	KERNEL=$4
	
	echo "OS: ${OS_STR}"
	echo "Version: ${OS_VER}"
	echo "Platform: ${PLATFORM}"
	if [ -n "${KERNEL}" ]; then
		echo "Kernel: ${KERNEL}"	
	fi
	echo "Latest ragent package is: ${PKG_NAME}"
	echo ""
	echo "The above is a recommendation only. It is not a guarantee of agent support."
	echo "For an official list of agent packages and their supported platforms, please see the latest SecureSphere Agent Release Notes."
	
	if [ -n "${PKG_VERB}" ]; then
		PKG_VERZ=`echo $PKG_VERB | awk -F"." '{print $1"."$2}'`
        if [ "${PKG_VERZ}" = "7.5" ] || [ "${PKG_VERZ}" = "8.0" ] || [ "${PKG_VERZ}" = "8.5" ]; then
            PKG_NAMEB=`echo ${PKG_NAME} | sed "s/-b.*-k/-b${PKG_VERB}-k/"`
        else
            PKG_NAMEB=`echo ${PKG_NAME} | sed "s/-b.*/-b${PKG_VERB}.tar.gz/"`
        fi

		echo "Patched ragent package is: ${PKG_NAMEB}"
    fi
	echo
	echo "*** Please verify that you run the latest version of which_ragent_package available at https://ftp-us.imperva.com ***"
  
}

get_pkg_name()
{
    version=${1}
    OS_STR=$2
    OS_VER=$3
    PLATFORM=$4
    KERNEL=$5
    
    if [ -z "${KERNEL}" ]; then
        # Ugly hack for Solaris which does not allow empty pattern in grep and for RHEL 3 plain 
        KERNEL=${OS_STR}
    fi
    
	# handle problematic cases in which kernel is smp and not largesmp, hugemum or pae
	if [ "${KERNEL}" = "SMP" ]; then
		PKG_NAME=`cat ${PKG_FILE} | grep -i "${version}" | grep -i "${OS_STR}" | grep -i "v${OS_VER}" | grep -i "p${PLATFORM}" | grep -i "${KERNEL}" | grep -v "hugemem" | grep -v "largesmp" | grep -v "pae" | awk -F" " '{print $NF}'`
	# handle problematic cases in which kernel is plain	
	elif [ "${KERNEL}" = "RHEL" ]; then
		PKG_NAME=`cat ${PKG_FILE} | grep -i "${version}" | grep -i "${OS_STR}" | grep -i "v${OS_VER}" | grep -i "p${PLATFORM}" | grep -i "${KERNEL}" | grep -v "smp" | grep -v "hugemem" | grep -v "largesmp" | grep -v "pae" | awk -F" " '{print $NF}'`
	# The following line is marked as a comment. It help debugging this script in case of wrong package name
	# echo "cat ${PKG_FILE} | grep -i "${version}" | grep -i "${OS_STR}" | grep -i "v${OS_VER}" | grep -i "p${PLATFORM}" | grep -i "${KERNEL}" | awk -F\" \" '{print \$NF}'"	 	
	else
		PKG_NAME=`cat ${PKG_FILE} | grep -i "${version}" | grep -i "${OS_STR}" | grep -i "v${OS_VER}" | grep -i "p${PLATFORM}" | grep -i "${KERNEL}" | head -1 | awk -F" " '{print $NF}'`
	fi
    
    if [ "${version}" = "9.5.0" ]; then
        if [ "${KERNEL}" = "UEK-v1-ik1" ]; then
            PKG_NAME="Imperva-ragent-OEL-v5-kUEK1-px86_64-b9.5.0.5009.tar.gz"
        elif [ "${KERNEL}" = "UEK-v1-ik2" ]; then
            PKG_NAME="Imperva-ragent-OEL-v5-kUEK2-px86_64-b9.5.0.5009.tar.gz"
        fi      
    fi

	if [ -z "${PKG_NAME}" ]; then
        if [ -z "${PKG_VERB}" ]; then
		    echo "Could not find appropriate package for version ${version} on this machine."
            if [ "${OS_STR}" = "SunOS" ] && [ "${OS_VER}" = "dummy" ]; then
                echo ""
                echo "Minimal Solaris 11.1 supported branch is: 0.175.1.15.0.4.0" 
                echo "Please upgrade the system to that branch or higher."
            fi
		    out 1
        fi
	fi
}

############################
###### Main flow ###########
############################
if [ -z "$1" ]; then
    extract_files
	usage
	out 0
fi
while [ -n "$1" ]
do
    switch=$1
    shift
    case ${switch} in
    -h) extract_files
	    usage 
		out 0;;
	-f) extract_files
		echo "Packages file: ${PKG_FILE}"
		echo "Kabi file: ${KABI_FILE}"
		exit 0;;
	-b) PKG_VERB=$1
        shift;;
    -v) PKG_VER=$1
		shift;;
	 *) extract_files
	    usage
		out 0;;
    esac
done

extract_files

if [ ! -f "${KABI_FILE}" -o ! -f "${PKG_FILE}" ]; then
	echo "Bsx extraction failed."
	out 1
fi

if [ -z "${PKG_VER}" ]; then
    if [ -z "${PKG_VERB}" ]; then
        usage
        out 0
	else
        PKG_VER=`echo $PKG_VERB | awk -F"." '{print $1"."$2}'`
        grep "RELEASE $PKG_VER" $PKG_FILE > /dev/null
        if [ $? -ne 0 ]; then
            PKG_VER=`cat $PKG_FILE | grep RELEASE | tail -n -1 | awk '{print $NF}'`
        fi
    fi
fi

INPUT_SMALL=`echo "$PKG_VER" | sed -e 's/[0-9]*\.[0-9]//'`
if [ -z "$INPUT_SMALL" ]; then
    PKG_VER=${PKG_VER}.0
fi

# We support only versions 9.0.0-11.5.0 for now, which can be found in packages.txt file
check_version_input $PKG_VER
if [ $? -eq 1 ]; then
    usage
    out 0
fi

get_sys_os
if [ "${SYS_OS}" = "Linux" ]; then
    if is_xen; then
        init_linux_xen_vars
		get_pkg_name "${PKG_VER}" "RHEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "XEN"
		print_pkg_name "RHEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "XEN"
	elif is_uek; then
		init_linux_uek_vars
		get_pkg_name "${PKG_VER}" "OEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SYS_KERNEL}"
		print_pkg_name "OEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SYS_KERNEL}"
	elif is_td; then
	    init_linux_td_vars
		get_pkg_name "${PKG_VER}" "TD-SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "${SYS_KERNEL}"
		print_pkg_name "TD-SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "${SYS_KERNEL}"
	elif is_suse; then
	    init_linux_suse_vars
		if [ "${PKG_VER}" = "8.0" -o "${PKG_VER}" = "8.5" ]; then
			SYS_DISTRO_VERSION="SLE${SYS_DISTRO_VERSION}"
		fi
		get_pkg_name "${PKG_VER}" "SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "${SYS_KERNEL_CONFIG}"
		print_pkg_name "SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "${SYS_KERNEL_CONFIG}"
	elif is_rhel; then
        init_linux_rhel_vars "${PKG_VER}"
		get_pkg_name "${PKG_VER}" "RHEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SMP_STRING}"
		print_pkg_name "RHEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SMP_STRING}"
	else
		echo "Unsupported Linux distribution"
		out 1
	fi
elif [ "${SYS_OS}" = "SunOS" ]; then
	init_sunos_vars
	get_pkg_name "${PKG_VER}" "SunOS" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
	print_pkg_name "SunOS" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
elif [ "${SYS_OS}" = "HPUX" ]; then
	init_hpux_vars
	PKG_VER_NUM=`echo "${PKG_VER}" | tr -d "."`
	if [ ${PKG_VER_NUM} -ge 90 ]; then
		SYS_DISTRO_VERSION=`uname -r | awk -F. '{print $2"."$3}'`
	else
		SYS_DISTRO_VERSION=`uname -r`
	fi
	get_pkg_name "${PKG_VER}" "HPUX" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
	print_pkg_name "HPUX" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
elif [ "${SYS_OS}" = "AIX" ]; then
	init_aix_vars
	get_pkg_name "${PKG_VER}" "AIX" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
	print_pkg_name "AIX" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
else
	echo "Unsupported OS"
	out 1
fi
out 0

__ARCHIVE1__

PACKAGES_VERSION 0089
RELEASE 9.0.0
aix		v52	powerpc32		aix	 Imperva-ragent-AIX-v52-ppowerpc32-b9.0.0.6015.tar.gz
aix		v52	powerpc64		aix	 Imperva-ragent-AIX-v52-ppowerpc64-b9.0.0.6015.tar.gz
aix		v53	powerpc32		aix	 Imperva-ragent-AIX-v53-ppowerpc32-b9.0.0.6015.tar.gz
aix		v53	powerpc64		aix	 Imperva-ragent-AIX-v53-ppowerpc64-b9.0.0.6015.tar.gz
aix		v61	powerpc64		aix	 Imperva-ragent-AIX-v61-ppowerpc64-b9.0.0.6023.tar.gz
aix		v71	powerpc64		aix	 Imperva-ragent-AIX-v71-ppowerpc64-b9.0.0.6023.tar.gz
hpux		v11.11	hppa		hpux	 Imperva-ragent-HPUX-v11.11-phppa-b9.0.0.6013.tar.gz
hpux		v11.23	hppa		hpux	 Imperva-ragent-HPUX-v11.23-phppa-b9.0.0.6013.tar.gz
hpux		v11.23	ia64		hpux	 Imperva-ragent-HPUX-v11.23-pia64-b9.0.0.6013.tar.gz
hpux		v11.31	hppa		hpux	 Imperva-ragent-HPUX-v11.31-phppa-b9.0.0.6014.tar.gz
hpux		v11.31	ia64		hpux	 Imperva-ragent-HPUX-v11.31-pia64-b9.0.0.6014.tar.gz
rhel		v3	i386		rhel	 Imperva-ragent-RHEL-v3-pi386-b9.0.0.6013.tar.gz
rhel		v3	i386		hugemem	 Imperva-ragent-RHEL-v3-kHUGEMEM-pi386-b9.0.0.6013.tar.gz
rhel		v3	i386		smp	 Imperva-ragent-RHEL-v3-kSMP-pi386-b9.0.0.6013.tar.gz
rhel		v3	x86_64		smp	 Imperva-ragent-RHEL-v3-kSMP-px86_64-b9.0.0.6013.tar.gz
rhel		v4	i386		smp	 Imperva-ragent-RHEL-v4-kSMP-pi386-b9.0.0.6017.tar.gz
rhel		v4	i386		hugemem	 Imperva-ragent-RHEL-v4-kHUGEMEM-pi386-b9.0.0.6017.tar.gz
rhel		v4	x86_64		largesmp	 Imperva-ragent-RHEL-v4-kLARGESMP-px86_64-b9.0.0.6017.tar.gz
rhel		v4	x86_64		smp	 Imperva-ragent-RHEL-v4-kSMP-px86_64-b9.0.0.6017.tar.gz
rhel		v5	i386		pae	 Imperva-ragent-RHEL-v5-kPAE-pi386-b9.0.0.6013.tar.gz
rhel		v5	i386		smp	 Imperva-ragent-RHEL-v5-kSMP-pi386-b9.0.0.6013.tar.gz
rhel		v5	x86_64		smp	 Imperva-ragent-RHEL-v5-kSMP-px86_64-b9.0.0.6013.tar.gz
sle		v9SP3	x86_64		smp	 Imperva-ragent-SLE-v9SP3-kSMP-px86_64-b9.0.0.6016.tar.gz
sle		v9SP4	x86_64		smp	 Imperva-ragent-SLE-v9SP4-kSMP-px86_64-b9.0.0.6016.tar.gz
sle		v10SP0	x86_64		smp	 Imperva-ragent-SLE-v10SP0-kSMP-px86_64-b9.0.0.6016.tar.gz
sle		v10SP1	x86_64		smp	 Imperva-ragent-SLE-v10SP1-kSMP-px86_64-b9.0.0.6016.tar.gz
sle		v10SP2	x86_64		smp	 Imperva-ragent-SLE-v10SP2-kSMP-px86_64-b9.0.0.6016.tar.gz
sle		v10SP3	x86_64		smp	 Imperva-ragent-SLE-v10SP3-kSMP-px86_64-b9.0.0.6016.tar.gz
sle		v10SP4	x86_64		smp	 Imperva-ragent-SLE-v10SP4-kSMP-px86_64-b9.0.0.6016.tar.gz
sle		v11SP1	x86_64		smp	 Imperva-ragent-SLE-v11SP1-kSMP-px86_64-b9.0.0.6016.tar.gz
SunOS		v5.10	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.10-psparcv9-b9.0.0.6013.tar.gz
SunOS		v5.10	x86_64		SunOS	 Imperva-ragent-SunOS-v5.10-px86_64-b9.0.0.6013.tar.gz
SunOS		v5.8	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.8-psparcv9-b9.0.0.6013.tar.gz
SunOS		v5.9	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.9-psparcv9-b9.0.0.6013.tar.gz
RELEASE 9.5.0
aix		v52	powerpc32		aix	 Imperva-ragent-AIX-v52-ppowerpc32-b9.5.0.5006.tar.gz
aix		v52	powerpc64		aix	 Imperva-ragent-AIX-v52-ppowerpc64-b9.5.0.5006.tar.gz
aix		v53	powerpc32		aix	 Imperva-ragent-AIX-v53-ppowerpc32-b9.5.0.5006.tar.gz
aix		v53	powerpc64		aix	 Imperva-ragent-AIX-v53-ppowerpc64-b9.5.0.5006.tar.gz
aix		v61	powerpc64		aix	 Imperva-ragent-AIX-v61-ppowerpc64-b9.5.0.5018.tar.gz
aix		v71	powerpc64		aix	 Imperva-ragent-AIX-v71-ppowerpc64-b9.5.0.5018.tar.gz
hpux		v11.11	hppa		hpux	 Imperva-ragent-HPUX-v11.11-phppa-b9.5.0.5006.tar.gz
hpux		v11.23	hppa		hpux	 Imperva-ragent-HPUX-v11.23-phppa-b9.5.0.5006.tar.gz
hpux		v11.23	ia64		hpux	 Imperva-ragent-HPUX-v11.23-pia64-b9.5.0.5006.tar.gz
hpux		v11.31	hppa		hpux	 Imperva-ragent-HPUX-v11.31-phppa-b9.5.0.5007.tar.gz
hpux		v11.31	ia64		hpux	 Imperva-ragent-HPUX-v11.31-pia64-b9.5.0.5007.tar.gz
oel		v5	x86_64		uek1	 Imperva-ragent-OEL-v5-kUEK1-px86_64-b9.5.0.5009.tar.gz
oel		v5	x86_64		uek2	 Imperva-ragent-OEL-v5-kUEK2-px86_64-b9.5.0.5009.tar.gz
rhel		v3	i386		rhel	 Imperva-ragent-RHEL-v3-pi386-b9.5.0.5006.tar.gz
rhel		v3	i386		hugemem	 Imperva-ragent-RHEL-v3-kHUGEMEM-pi386-b9.5.0.5006.tar.gz
rhel		v3	i386		smp	 Imperva-ragent-RHEL-v3-kSMP-pi386-b9.5.0.5006.tar.gz
rhel		v3	x86_64		smp	 Imperva-ragent-RHEL-v3-kSMP-px86_64-b9.5.0.5006.tar.gz
rhel		v4	i386		smp	 Imperva-ragent-RHEL-v4-kSMP-pi386-b9.5.0.5011.tar.gz
rhel		v4	i386		hugemem	 Imperva-ragent-RHEL-v4-kHUGEMEM-pi386-b9.5.0.5011.tar.gz
rhel		v4	x86_64		largesmp	 Imperva-ragent-RHEL-v4-kLARGESMP-px86_64-b9.5.0.5011.tar.gz
rhel		v4	x86_64		smp	 Imperva-ragent-RHEL-v4-kSMP-px86_64-b9.5.0.5011.tar.gz
rhel		v5	i386		pae	 Imperva-ragent-RHEL-v5-kPAE-pi386-b9.5.0.5006.tar.gz
rhel		v5	i386		smp	 Imperva-ragent-RHEL-v5-kSMP-pi386-b9.5.0.5006.tar.gz
rhel		v5	x86_64		smp	 Imperva-ragent-RHEL-v5-kSMP-px86_64-b9.5.0.5006.tar.gz
rhel		v5	x86_64		xen	 Imperva-ragent-RHEL-v5-kXEN-px86_64-b9.5.0.5006.tar.gz
rhel		v6K0	i386		smp	 Imperva-ragent-RHEL-v6K0-kSMP-pi386-b9.5.0.5006.tar.gz
rhel		v6K1	i386		smp	 Imperva-ragent-RHEL-v6K1-kSMP-pi386-b9.5.0.5006.tar.gz
rhel		v6K0	x86_64		smp	 Imperva-ragent-RHEL-v6K0-kSMP-px86_64-b9.5.0.5006.tar.gz
rhel		v6K1	x86_64		smp	 Imperva-ragent-RHEL-v6K1-kSMP-px86_64-b9.5.0.5006.tar.gz
sle		v9SP3	x86_64		smp	 Imperva-ragent-SLE-v9SP3-kSMP-px86_64-b9.5.0.5006.tar.gz
sle		v9SP4	x86_64		smp	 Imperva-ragent-SLE-v9SP4-kSMP-px86_64-b9.5.0.5006.tar.gz
sle		v10SP0	x86_64		smp	 Imperva-ragent-SLE-v10SP0-kSMP-px86_64-b9.5.0.5006.tar.gz
sle		v10SP1	x86_64		smp	 Imperva-ragent-SLE-v10SP1-kSMP-px86_64-b9.5.0.5006.tar.gz
sle		v10SP2	x86_64		smp	 Imperva-ragent-SLE-v10SP2-kSMP-px86_64-b9.5.0.5006.tar.gz
sle		v10SP3	x86_64		smp	 Imperva-ragent-SLE-v10SP3-kSMP-px86_64-b9.5.0.5006.tar.gz
sle		v10SP4	x86_64		smp	 Imperva-ragent-SLE-v10SP4-kSMP-px86_64-b9.5.0.5006.tar.gz
sle		v11SP1	x86_64		smp	 Imperva-ragent-SLE-v11SP1-kSMP-px86_64-b9.5.0.5006.tar.gz
SunOS		v5.10	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.10-psparcv9-b9.5.0.5006.tar.gz
SunOS		v5.10	x86_64		SunOS	 Imperva-ragent-SunOS-v5.10-px86_64-b9.5.0.5006.tar.gz
SunOS		v5.8	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.8-psparcv9-b9.5.0.5006.tar.gz
SunOS		v5.9	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.9-psparcv9-b9.5.0.5006.tar.gz
SunOS		v5.11	x86_64		SunOS	 Imperva-ragent-SunOS-v5.11-px86_64-b9.5.0.5006.tar.gz
RELEASE 10.0.0
aix		v52	powerpc32		aix	 Imperva-ragent-AIX-v52-ppowerpc32-b10.0.0.5023.tar.gz
aix		v52	powerpc64		aix	 Imperva-ragent-AIX-v52-ppowerpc64-b10.0.0.5023.tar.gz
aix		v53	powerpc32		aix	 Imperva-ragent-AIX-v53-ppowerpc32-b10.0.0.5023.tar.gz
aix		v53	powerpc64		aix	 Imperva-ragent-AIX-v53-ppowerpc64-b10.0.0.5023.tar.gz
aix		v61	powerpc64		aix	 Imperva-ragent-AIX-v61-ppowerpc64-b10.0.0.5023.tar.gz
aix		v71	powerpc64		aix	 Imperva-ragent-AIX-v71-ppowerpc64-b10.0.0.5023.tar.gz
hpux		v11.11	hppa		hpux	 Imperva-ragent-HPUX-v11.11-phppa-b10.0.0.5023.tar.gz
hpux		v11.23	hppa		hpux	 Imperva-ragent-HPUX-v11.23-phppa-b10.0.0.5023.tar.gz
hpux		v11.23	ia64		hpux	 Imperva-ragent-HPUX-v11.23-pia64-b10.0.0.5032.tar.gz
hpux		v11.31	hppa		hpux	 Imperva-ragent-HPUX-v11.31-phppa-b10.0.0.5023.tar.gz
hpux		v11.31	ia64		hpux	 Imperva-ragent-HPUX-v11.31-pia64-b10.0.0.5026.tar.gz
oel		v5	x86_64		uek-v1-ik1	 Imperva-ragent-OEL-v5-kUEK-v1-ik1-px86_64-b10.0.0.5023.tar.gz
oel		v5	x86_64		uek-v1-ik2	 Imperva-ragent-OEL-v5-kUEK-v1-ik2-px86_64-b10.0.0.5023.tar.gz
oel		v5	x86_64		uek-v1-ik3	 Imperva-ragent-OEL-v5-kUEK-v1-ik3-px86_64-b10.0.0.5023.tar.gz
oel		v6	x86_64		uek-v2	 Imperva-ragent-OEL-v6-kUEK-v2-px86_64-b10.0.0.5023.tar.gz
rhel		v3	i386		rhel	 Imperva-ragent-RHEL-v3-pi386-b10.0.0.5023.tar.gz
rhel		v3	i386		hugemem	 Imperva-ragent-RHEL-v3-kHUGEMEM-pi386-b10.0.0.5023.tar.gz
rhel		v3	i386		smp	 Imperva-ragent-RHEL-v3-kSMP-pi386-b10.0.0.5023.tar.gz
rhel		v3	x86_64		smp	 Imperva-ragent-RHEL-v3-kSMP-px86_64-b10.0.0.5023.tar.gz
rhel		v4	i386		smp	 Imperva-ragent-RHEL-v4-kSMP-pi386-b10.0.0.5023.tar.gz
rhel		v4	i386		hugemem	 Imperva-ragent-RHEL-v4-kHUGEMEM-pi386-b10.0.0.5023.tar.gz
rhel		v4	x86_64		largesmp	 Imperva-ragent-RHEL-v4-kLARGESMP-px86_64-b10.0.0.5023.tar.gz
rhel		v4	x86_64		smp	 Imperva-ragent-RHEL-v4-kSMP-px86_64-b10.0.0.5023.tar.gz
rhel		v5	i386		pae	 Imperva-ragent-RHEL-v5-kPAE-pi386-b10.0.0.5023.tar.gz
rhel		v5	i386		smp	 Imperva-ragent-RHEL-v5-kSMP-pi386-b10.0.0.5023.tar.gz
rhel		v5	x86_64		smp	 Imperva-ragent-RHEL-v5-kSMP-px86_64-b10.0.0.5023.tar.gz
rhel		v5	x86_64		xen	 Imperva-ragent-RHEL-v5-kXEN-px86_64-b10.0.0.5023.tar.gz
rhel		v6	i386		smp	 Imperva-ragent-RHEL-v6-kSMP-pi386-b10.0.0.5023.tar.gz
rhel		v6	x86_64		smp	 Imperva-ragent-RHEL-v6-kSMP-px86_64-b10.0.0.5023.tar.gz
sle		v9SP3	x86_64		smp	 Imperva-ragent-SLE-v9SP3-kSMP-px86_64-b10.0.0.5023.tar.gz
sle		v9SP3	i386		smp	 Imperva-ragent-SLE-v9SP3-kSMP-pi386-b10.0.0.5023.tar.gz
sle		v9SP4	x86_64		smp	 Imperva-ragent-SLE-v9SP4-kSMP-px86_64-b10.0.0.5023.tar.gz
sle		v10SP0	x86_64		smp	 Imperva-ragent-SLE-v10SP0-kSMP-px86_64-b10.0.0.5023.tar.gz
sle		v10SP1	x86_64		smp	 Imperva-ragent-SLE-v10SP1-kSMP-px86_64-b10.0.0.5023.tar.gz
sle		v10SP2	x86_64		smp	 Imperva-ragent-SLE-v10SP2-kSMP-px86_64-b10.0.0.5023.tar.gz
sle		v10SP3	x86_64		smp	 Imperva-ragent-SLE-v10SP3-kSMP-px86_64-b10.0.0.5023.tar.gz
sle		v10SP4	x86_64		smp	 Imperva-ragent-SLE-v10SP4-kSMP-px86_64-b10.0.0.5023.tar.gz
sle		v11SP0	i386		pae	 Imperva-ragent-SLE-v11SP0-kPAE-pi386-b10.0.0.5023.tar.gz
sle		v11SP1	x86_64		smp	 Imperva-ragent-SLE-v11SP1-kSMP-px86_64-b10.0.0.5023.tar.gz
sle		v11SP2	x86_64		smp	 Imperva-ragent-SLE-v11SP2-kSMP-px86_64-b10.0.0.5023.tar.gz
sle		v11SP3	x86_64		smp	 Imperva-ragent-SLE-v11SP3-kSMP-px86_64-b10.0.0.5023.tar.gz
SunOS		v5.10	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.10-psparcv9-b10.0.0.5024.tar.gz
SunOS		v5.10	x86_64		SunOS	 Imperva-ragent-SunOS-v5.10-px86_64-b10.0.0.5024.tar.gz
SunOS		v5.8	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.8-psparcv9-b10.0.0.5024.tar.gz
SunOS		v5.9	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.9-psparcv9-b10.0.0.5024.tar.gz
SunOS		v5.11	x86_64		SunOS	 Imperva-ragent-SunOS-v5.11-px86_64-b10.0.0.5024.tar.gz
SunOS		v5.11	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.11-psparcv9-b10.0.0.5024.tar.gz
TD-SLE		v11SP1	x86_64		TD	 Imperva-ragent-TD-SLE-v11SP1-kTD-px86_64-b10.0.0.5023.tar.gz
RELEASE 10.5.0
aix		v52	powerpc32		aix	 Imperva-ragent-AIX-v52-ppowerpc32-b10.5.0.5023.tar.gz
aix		v52	powerpc64		aix	 Imperva-ragent-AIX-v52-ppowerpc64-b10.5.0.5023.tar.gz
aix		v53	powerpc32		aix	 Imperva-ragent-AIX-v53-ppowerpc32-b10.5.0.5023.tar.gz
aix		v53	powerpc64		aix	 Imperva-ragent-AIX-v53-ppowerpc64-b10.5.0.5023.tar.gz
aix		v61	powerpc64		aix	 Imperva-ragent-AIX-v61-ppowerpc64-b10.5.0.5023.tar.gz
aix		v71	powerpc64		aix	 Imperva-ragent-AIX-v71-ppowerpc64-b10.5.0.5023.tar.gz
hpux		v11.11	hppa		hpux	 Imperva-ragent-HPUX-v11.11-phppa-b10.5.0.5023.tar.gz
hpux		v11.23	hppa		hpux	 Imperva-ragent-HPUX-v11.23-phppa-b10.5.0.5023.tar.gz
hpux		v11.23	ia64		hpux	 Imperva-ragent-HPUX-v11.23-pia64-b10.5.0.5032.tar.gz
hpux		v11.31	hppa		hpux	 Imperva-ragent-HPUX-v11.31-phppa-b10.5.0.5023.tar.gz
hpux		v11.31	ia64		hpux	 Imperva-ragent-HPUX-v11.31-pia64-b10.5.0.5026.tar.gz
oel		v5	x86_64		uek-v1-ik1	 Imperva-ragent-OEL-v5-kUEK-v1-ik1-px86_64-b10.5.0.5023.tar.gz
oel		v5	x86_64		uek-v1-ik2	 Imperva-ragent-OEL-v5-kUEK-v1-ik2-px86_64-b10.5.0.5023.tar.gz
oel		v5	x86_64		uek-v1-ik3	 Imperva-ragent-OEL-v5-kUEK-v1-ik3-px86_64-b10.5.0.5023.tar.gz
oel		v6	x86_64		uek-v2	 Imperva-ragent-OEL-v6-kUEK-v2-px86_64-b10.5.0.5023.tar.gz
oel		v5	x86_64		uek-v1-ik4	 Imperva-ragent-OEL-v5-kUEK-v1-ik4-px86_64-b10.5.0.5023.tar.gz
oel		v5	x86_64		uek-v2	 Imperva-ragent-OEL-v5-kUEK-v2-px86_64-b10.5.0.5023.tar.gz
oel		v6	x86_64		uek-v3	 Imperva-ragent-OEL-v6-kUEK-v3-px86_64-b10.5.0.5023.tar.gz
rhel		v3	i386		rhel	 Imperva-ragent-RHEL-v3-pi386-b10.5.0.5023.tar.gz
rhel		v3	i386		hugemem	 Imperva-ragent-RHEL-v3-kHUGEMEM-pi386-b10.5.0.5023.tar.gz
rhel		v3	i386		smp	 Imperva-ragent-RHEL-v3-kSMP-pi386-b10.5.0.5023.tar.gz
rhel		v3	x86_64		smp	 Imperva-ragent-RHEL-v3-kSMP-px86_64-b10.5.0.5023.tar.gz
rhel		v4	i386		smp	 Imperva-ragent-RHEL-v4-kSMP-pi386-b10.5.0.5023.tar.gz
rhel		v4	i386		hugemem	 Imperva-ragent-RHEL-v4-kHUGEMEM-pi386-b10.5.0.5023.tar.gz
rhel		v4	x86_64		largesmp	 Imperva-ragent-RHEL-v4-kLARGESMP-px86_64-b10.5.0.5023.tar.gz
rhel		v4	x86_64		smp	 Imperva-ragent-RHEL-v4-kSMP-px86_64-b10.5.0.5023.tar.gz
rhel		v5	i386		pae	 Imperva-ragent-RHEL-v5-kPAE-pi386-b10.5.0.5023.tar.gz
rhel		v5	i386		smp	 Imperva-ragent-RHEL-v5-kSMP-pi386-b10.5.0.5023.tar.gz
rhel		v5	x86_64		smp	 Imperva-ragent-RHEL-v5-kSMP-px86_64-b10.5.0.5023.tar.gz
rhel		v5	x86_64		xen	 Imperva-ragent-RHEL-v5-kXEN-px86_64-b10.5.0.5023.tar.gz
rhel		v6	i386		smp	 Imperva-ragent-RHEL-v6-kSMP-pi386-b10.5.0.5023.tar.gz
rhel		v6	x86_64		smp	 Imperva-ragent-RHEL-v6-kSMP-px86_64-b10.5.0.5023.tar.gz
sle		v9SP3	x86_64		smp	 Imperva-ragent-SLE-v9SP3-kSMP-px86_64-b10.5.0.5023.tar.gz
sle		v9SP3	i386		smp	 Imperva-ragent-SLE-v9SP3-kSMP-pi386-b10.5.0.5023.tar.gz
sle		v9SP4	x86_64		smp	 Imperva-ragent-SLE-v9SP4-kSMP-px86_64-b10.5.0.5023.tar.gz
sle		v10SP0	x86_64		smp	 Imperva-ragent-SLE-v10SP0-kSMP-px86_64-b10.5.0.5023.tar.gz
sle		v10SP1	x86_64		smp	 Imperva-ragent-SLE-v10SP1-kSMP-px86_64-b10.5.0.5023.tar.gz
sle		v10SP2	x86_64		smp	 Imperva-ragent-SLE-v10SP2-kSMP-px86_64-b10.5.0.5023.tar.gz
sle		v10SP3	x86_64		smp	 Imperva-ragent-SLE-v10SP3-kSMP-px86_64-b10.5.0.5023.tar.gz
sle		v10SP4	x86_64		smp	 Imperva-ragent-SLE-v10SP4-kSMP-px86_64-b10.5.0.5023.tar.gz
sle		v11SP0	i386		pae	 Imperva-ragent-SLE-v11SP0-kPAE-pi386-b10.5.0.5023.tar.gz
sle		v11SP1	x86_64		smp	 Imperva-ragent-SLE-v11SP1-kSMP-px86_64-b10.5.0.5023.tar.gz
sle		v11SP2	x86_64		smp	 Imperva-ragent-SLE-v11SP2-kSMP-px86_64-b10.5.0.5023.tar.gz
sle		v11SP3	x86_64		smp	 Imperva-ragent-SLE-v11SP3-kSMP-px86_64-b10.5.0.5023.tar.gz
SunOS		v5.10	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.10-psparcv9-b10.5.0.5024.tar.gz
SunOS		v5.10	x86_64		SunOS	 Imperva-ragent-SunOS-v5.10-px86_64-b10.5.0.5024.tar.gz
SunOS		v5.8	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.8-psparcv9-b10.5.0.5024.tar.gz
SunOS		v5.9	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.9-psparcv9-b10.5.0.5024.tar.gz
SunOS		v5.11	x86_64		SunOS	 Imperva-ragent-SunOS-v5.11-px86_64-b10.5.0.5024.tar.gz
SunOS		v5.11	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.11-psparcv9-b10.5.0.5024.tar.gz
TD-SLE		v11SP1	x86_64		TD	 Imperva-ragent-TD-SLE-v11SP1-kTD-px86_64-b10.5.0.5023.tar.gz
TD-SLE		v10SP3	x86_64		TD	 Imperva-ragent-TD-SLE-v10SP3-kTD-px86_64-b10.5.0.5023.tar.gz
RELEASE 11.0.0
aix		v52	powerpc32		aix	 Imperva-ragent-AIX-v52-ppowerpc32-b11.0.0.4028.tar.gz
aix		v52	powerpc64		aix	 Imperva-ragent-AIX-v52-ppowerpc64-b11.0.0.4028.tar.gz
aix		v53	powerpc32		aix	 Imperva-ragent-AIX-v53-ppowerpc32-b11.0.0.4028.tar.gz
aix		v53	powerpc64		aix	 Imperva-ragent-AIX-v53-ppowerpc64-b11.0.0.4028.tar.gz
aix		v61	powerpc64		aix	 Imperva-ragent-AIX-v61-ppowerpc64-b11.0.0.4028.tar.gz
aix		v71	powerpc64		aix	 Imperva-ragent-AIX-v71-ppowerpc64-b11.0.0.4029.tar.gz
hpux		v11.11	hppa		hpux	 Imperva-ragent-HPUX-v11.11-phppa-b11.0.0.4028.tar.gz
hpux		v11.23	hppa		hpux	 Imperva-ragent-HPUX-v11.23-phppa-b11.0.0.4028.tar.gz
hpux		v11.23	ia64		hpux	 Imperva-ragent-HPUX-v11.23-pia64-b11.0.0.4032.tar.gz
hpux		v11.31	hppa		hpux	 Imperva-ragent-HPUX-v11.31-phppa-b11.0.0.4028.tar.gz
hpux		v11.31	ia64		hpux	 Imperva-ragent-HPUX-v11.31-pia64-b11.0.0.4032.tar.gz
oel		v5	x86_64		uek-v1-ik1	 Imperva-ragent-OEL-v5-kUEK-v1-ik1-px86_64-b11.0.0.4028.tar.gz
oel		v5	x86_64		uek-v1-ik2	 Imperva-ragent-OEL-v5-kUEK-v1-ik2-px86_64-b11.0.0.4028.tar.gz
oel		v5	x86_64		uek-v1-ik3	 Imperva-ragent-OEL-v5-kUEK-v1-ik3-px86_64-b11.0.0.4028.tar.gz
oel		v6	x86_64		uek-v2	 Imperva-ragent-OEL-v6-kUEK-v2-px86_64-b11.0.0.4028.tar.gz
oel		v5	x86_64		uek-v1-ik4	 Imperva-ragent-OEL-v5-kUEK-v1-ik4-px86_64-b11.0.0.4028.tar.gz
oel		v5	x86_64		uek-v2	 Imperva-ragent-OEL-v5-kUEK-v2-px86_64-b11.0.0.4028.tar.gz
oel		v6	x86_64		uek-v3	 Imperva-ragent-OEL-v6-kUEK-v3-px86_64-b11.0.0.4028.tar.gz
rhel		v3	i386		rhel	 Imperva-ragent-RHEL-v3-pi386-b11.0.0.4028.tar.gz
rhel		v3	i386		hugemem	 Imperva-ragent-RHEL-v3-kHUGEMEM-pi386-b11.0.0.4028.tar.gz
rhel		v3	i386		smp	 Imperva-ragent-RHEL-v3-kSMP-pi386-b11.0.0.4028.tar.gz
rhel		v3	x86_64		smp	 Imperva-ragent-RHEL-v3-kSMP-px86_64-b11.0.0.4028.tar.gz
rhel		v4	i386		smp	 Imperva-ragent-RHEL-v4-kSMP-pi386-b11.0.0.4028.tar.gz
rhel		v4	i386		hugemem	 Imperva-ragent-RHEL-v4-kHUGEMEM-pi386-b11.0.0.4028.tar.gz
rhel		v4	x86_64		largesmp	 Imperva-ragent-RHEL-v4-kLARGESMP-px86_64-b11.0.0.4028.tar.gz
rhel		v4	x86_64		smp	 Imperva-ragent-RHEL-v4-kSMP-px86_64-b11.0.0.4028.tar.gz
rhel		v5	i386		pae	 Imperva-ragent-RHEL-v5-kPAE-pi386-b11.0.0.4028.tar.gz
rhel		v5	i386		smp	 Imperva-ragent-RHEL-v5-kSMP-pi386-b11.0.0.4028.tar.gz
rhel		v5	x86_64		smp	 Imperva-ragent-RHEL-v5-kSMP-px86_64-b11.0.0.4028.tar.gz
rhel		v5	x86_64		xen	 Imperva-ragent-RHEL-v5-kXEN-px86_64-b11.0.0.4028.tar.gz
rhel		v6	i386		smp	 Imperva-ragent-RHEL-v6-kSMP-pi386-b11.0.0.4028.tar.gz
rhel		v6	x86_64		smp	 Imperva-ragent-RHEL-v6-kSMP-px86_64-b11.0.0.4029.tar.gz
rhel		v7	x86_64		smp	 Imperva-ragent-RHEL-v7-kSMP-px86_64-b11.0.0.4028.tar.gz
sle		v9SP3	x86_64		smp	 Imperva-ragent-SLE-v9SP3-kSMP-px86_64-b11.0.0.4028.tar.gz
sle		v9SP3	i386		smp	 Imperva-ragent-SLE-v9SP3-kSMP-pi386-b11.0.0.4028.tar.gz
sle		v9SP4	x86_64		smp	 Imperva-ragent-SLE-v9SP4-kSMP-px86_64-b11.0.0.4028.tar.gz
sle		v10SP0	x86_64		smp	 Imperva-ragent-SLE-v10SP0-kSMP-px86_64-b11.0.0.4028.tar.gz
sle		v10SP1	x86_64		smp	 Imperva-ragent-SLE-v10SP1-kSMP-px86_64-b11.0.0.4028.tar.gz
sle		v10SP2	x86_64		smp	 Imperva-ragent-SLE-v10SP2-kSMP-px86_64-b11.0.0.4028.tar.gz
sle		v10SP3	x86_64		smp	 Imperva-ragent-SLE-v10SP3-kSMP-px86_64-b11.0.0.4028.tar.gz
sle		v10SP4	x86_64		smp	 Imperva-ragent-SLE-v10SP4-kSMP-px86_64-b11.0.0.4028.tar.gz
sle		v11SP0	i386		pae	 Imperva-ragent-SLE-v11SP0-kPAE-pi386-b11.0.0.4028.tar.gz
sle		v11SP1	x86_64		smp	 Imperva-ragent-SLE-v11SP1-kSMP-px86_64-b11.0.0.4028.tar.gz
sle		v11SP2	x86_64		smp	 Imperva-ragent-SLE-v11SP2-kSMP-px86_64-b11.0.0.4028.tar.gz
sle		v11SP3	x86_64		smp	 Imperva-ragent-SLE-v11SP3-kSMP-px86_64-b11.0.0.4028.tar.gz
SunOS		v5.10	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.10-psparcv9-b11.0.0.4028.tar.gz
SunOS		v5.10	x86_64		SunOS	 Imperva-ragent-SunOS-v5.10-px86_64-b11.0.0.4028.tar.gz
SunOS		v5.8	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.8-psparcv9-b11.0.0.4028.tar.gz
SunOS		v5.9	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.9-psparcv9-b11.0.0.4028.tar.gz
SunOS		v5.11	x86_64		SunOS	 Imperva-ragent-SunOS-v5.11-px86_64-b11.0.0.4028.tar.gz
SunOS		v5.11	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.11-psparcv9-b11.0.0.4028.tar.gz
TD-SLE		v11SP1	x86_64		TD	 Imperva-ragent-TD-SLE-v11SP1-kTD-px86_64-b11.0.0.4028.tar.gz
TD-SLE		v11SP1	x86_64		TD-ik2	 Imperva-ragent-TD-SLE-v11SP1-kTD-ik2-px86_64-b11.0.0.4028.tar.gz
TD-SLE		v10SP3	x86_64		TD	 Imperva-ragent-TD-SLE-v10SP3-kTD-px86_64-b11.0.0.4028.tar.gz
RELEASE 11.0.1
rhel		v5	x86_64		smp	 Imperva-ragent-RHEL-v5-kSMP-px86_64-b11.0.1.2001.tar.gz
rhel		v6	x86_64		smp	 Imperva-ragent-RHEL-v6-kSMP-px86_64-b11.0.1.2001.tar.gz
sle		v11SP2	x86_64		smp	 Imperva-ragent-SLE-v11SP2-kSMP-px86_64-b11.0.1.2001.tar.gz
RELEASE 11.5.0
aix		v52	powerpc32		aix	 Imperva-ragent-AIX-v52-ppowerpc32-b11.5.0.2032.tar.gz
aix		v52	powerpc64		aix	 Imperva-ragent-AIX-v52-ppowerpc64-b11.5.0.2032.tar.gz
aix		v53	powerpc32		aix	 Imperva-ragent-AIX-v53-ppowerpc32-b11.5.0.2032.tar.gz
aix		v53	powerpc64		aix	 Imperva-ragent-AIX-v53-ppowerpc64-b11.5.0.2032.tar.gz
aix		v61	powerpc64		aix	 Imperva-ragent-AIX-v61-ppowerpc64-b11.5.0.2032.tar.gz
aix		v71	powerpc64		aix	 Imperva-ragent-AIX-v71-ppowerpc64-b11.5.0.2032.tar.gz
hpux		v11.11	hppa		hpux	 Imperva-ragent-HPUX-v11.11-phppa-b11.5.0.2032.tar.gz
hpux		v11.23	hppa		hpux	 Imperva-ragent-HPUX-v11.23-phppa-b11.5.0.2032.tar.gz
hpux		v11.23	ia64		hpux	 Imperva-ragent-HPUX-v11.23-pia64-b11.5.0.2036.tar.gz
hpux		v11.31	hppa		hpux	 Imperva-ragent-HPUX-v11.31-phppa-b11.5.0.2032.tar.gz
hpux		v11.31	ia64		hpux	 Imperva-ragent-HPUX-v11.31-pia64-b11.5.0.2036.tar.gz
oel		v5	x86_64		uek-v1-ik1	 Imperva-ragent-OEL-v5-kUEK-v1-ik1-px86_64-b11.5.0.2032.tar.gz
oel		v5	x86_64		uek-v1-ik2	 Imperva-ragent-OEL-v5-kUEK-v1-ik2-px86_64-b11.5.0.2032.tar.gz
oel		v5	x86_64		uek-v1-ik3	 Imperva-ragent-OEL-v5-kUEK-v1-ik3-px86_64-b11.5.0.2032.tar.gz
oel		v6	x86_64		uek-v2	 Imperva-ragent-OEL-v6-kUEK-v2-px86_64-b11.5.0.2032.tar.gz
oel		v5	x86_64		uek-v1-ik4	 Imperva-ragent-OEL-v5-kUEK-v1-ik4-px86_64-b11.5.0.2032.tar.gz
oel		v5	x86_64		uek-v2	 Imperva-ragent-OEL-v5-kUEK-v2-px86_64-b11.5.0.2032.tar.gz
oel		v6	x86_64		uek-v3	 Imperva-ragent-OEL-v6-kUEK-v3-px86_64-b11.5.0.2032.tar.gz
oel		v7	x86_64		uek-v3	 Imperva-ragent-OEL-v7-kUEK-v3-px86_64-b11.5.0.2032.tar.gz
rhel		v3	i386		rhel	 Imperva-ragent-RHEL-v3-pi386-b11.5.0.2032.tar.gz
rhel		v3	i386		hugemem	 Imperva-ragent-RHEL-v3-kHUGEMEM-pi386-b11.5.0.2032.tar.gz
rhel		v3	i386		smp	 Imperva-ragent-RHEL-v3-kSMP-pi386-b11.5.0.2032.tar.gz
rhel		v3	x86_64		smp	 Imperva-ragent-RHEL-v3-kSMP-px86_64-b11.5.0.2032.tar.gz
rhel		v4	i386		smp	 Imperva-ragent-RHEL-v4-kSMP-pi386-b11.5.0.2032.tar.gz
rhel		v4	i386		hugemem	 Imperva-ragent-RHEL-v4-kHUGEMEM-pi386-b11.5.0.2032.tar.gz
rhel		v4	x86_64		largesmp	 Imperva-ragent-RHEL-v4-kLARGESMP-px86_64-b11.5.0.2032.tar.gz
rhel		v4	x86_64		smp	 Imperva-ragent-RHEL-v4-kSMP-px86_64-b11.5.0.2032.tar.gz
rhel		v5	i386		pae	 Imperva-ragent-RHEL-v5-kPAE-pi386-b11.5.0.2032.tar.gz
rhel		v5	i386		smp	 Imperva-ragent-RHEL-v5-kSMP-pi386-b11.5.0.2032.tar.gz
rhel		v5	x86_64		smp	 Imperva-ragent-RHEL-v5-kSMP-px86_64-b11.5.0.2032.tar.gz
rhel		v5	x86_64		xen	 Imperva-ragent-RHEL-v5-kXEN-px86_64-b11.5.0.2032.tar.gz
rhel		v6	i386		smp	 Imperva-ragent-RHEL-v6-kSMP-pi386-b11.5.0.2032.tar.gz
rhel		v6	x86_64		smp	 Imperva-ragent-RHEL-v6-kSMP-px86_64-b11.5.0.2033.tar.gz
rhel		v7	x86_64		smp	 Imperva-ragent-RHEL-v7-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v9SP3	x86_64		smp	 Imperva-ragent-SLE-v9SP3-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v9SP3	i386		smp	 Imperva-ragent-SLE-v9SP3-kSMP-pi386-b11.5.0.2032.tar.gz
sle		v9SP4	x86_64		smp	 Imperva-ragent-SLE-v9SP4-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v10SP0	x86_64		smp	 Imperva-ragent-SLE-v10SP0-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v10SP1	x86_64		smp	 Imperva-ragent-SLE-v10SP1-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v10SP2	x86_64		smp	 Imperva-ragent-SLE-v10SP2-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v10SP3	x86_64		smp	 Imperva-ragent-SLE-v10SP3-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v10SP4	x86_64		smp	 Imperva-ragent-SLE-v10SP4-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v11SP0	i386		pae	 Imperva-ragent-SLE-v11SP0-kPAE-pi386-b11.5.0.2032.tar.gz
sle		v11SP1	x86_64		smp	 Imperva-ragent-SLE-v11SP1-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v11SP2	x86_64		smp	 Imperva-ragent-SLE-v11SP2-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v11SP3	x86_64		smp	 Imperva-ragent-SLE-v11SP3-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v11SP4	x86_64		smp	 Imperva-ragent-SLE-v11SP4-kSMP-px86_64-b11.5.0.2032.tar.gz
sle		v12SP0	x86_64		smp	 Imperva-ragent-SLE-v12SP0-kSMP-px86_64-b11.5.0.2032.tar.gz
SunOS		v5.10	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.10-psparcv9-b11.5.0.2032.tar.gz
SunOS		v5.10	x86_64		SunOS	 Imperva-ragent-SunOS-v5.10-px86_64-b11.5.0.2032.tar.gz
SunOS		v5.8	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.8-psparcv9-b11.5.0.2032.tar.gz
SunOS		v5.9	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.9-psparcv9-b11.5.0.2032.tar.gz
SunOS		v5.11	x86_64		SunOS	 Imperva-ragent-SunOS-v5.11-px86_64-b11.5.0.2032.tar.gz
SunOS		v5.11	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.11-psparcv9-b11.5.0.2032.tar.gz
TD-SLE		v11SP1	x86_64		TD	 Imperva-ragent-TD-SLE-v11SP1-kTD-px86_64-b11.5.0.2032.tar.gz
TD-SLE		v11SP1	x86_64		TD-ik2	 Imperva-ragent-TD-SLE-v11SP1-kTD-ik2-px86_64-b11.5.0.2032.tar.gz
TD-SLE		v10SP3	x86_64		TD	 Imperva-ragent-TD-SLE-v10SP3-kTD-px86_64-b11.5.0.2032.tar.gz
RELEASE 11.5.1
rhel		v6	x86_64		smp	 Imperva-ragent-RHEL-v6-kSMP-px86_64-b11.5.1.2011.tar.gz
__ARCHIVE2__
KABI_VERSION 0057
#dist               agent sig       min kern patch      max kern patch        additional_os_info  optional_data
SLE.9.3.i386        0               0                   99999              
SLE.9.3.x86_64      2481918936      0                   99999              
SLE.9.3.x86_64      3766268762      0                   99999              
SLE.9.4.x86_64      3384926936      0                   99999              
SLE.9.4.x86_64      3686701036      0                   99999              
SLE.10.1.x86_64     2103713736      0                   99999              
SLE.10.1.x86_64     2350452553      0                   99999              
SLE.10.1.x86_64     3542803736      0                   99999              
SLE.10.2.x86_64     2103713736      0                   99999              
SLE.10.2.x86_64     2350452553      0                   99999              
SLE.10.2.x86_64     3542803736      0                   99999
SLE.10.3.x86_64     2103713736      0                   99999
SLE.10.3.x86_64     2350452553      0                   99999
SLE.10.3.x86_64     3542803736      0                   99999
SLE.10.4.x86_64     2350452553      0                   99999              
SLE.10.4.x86_64     3542803736      0                   99999
SLE.10.0.x86_64     2103713736      0                   99999
SLE.10.0.x86_64     2350452553      0                   99999              
SLE.10.0.x86_64     3542803736      0                   99999
SLE.11.0.i386       0               0                   99999
SLE.11.1.x86_64     28697893        0                   99999
SLE.11.1.x86_64     3553360080      0                   99999              
SLE.11.1.x86_64     1954018875      0                   99999
SLE.11.2.x86_64     2350452559      0                   99999
SLE.11.3.x86_64     0               0                   99999
SLE.11.4.x86_64     0               0                   99999
SLE.12.0.x86_64     0               0                   99999     
SLE.12.1.x86_64     0               0                   99999      
UEK1                0               2.6.32-100.26.2     2.6.32-100.26.2       el5                 UEK-v1-ik1
UEK2                0               2.6.32-300.7.1      2.6.32-300.39.2       el5                 UEK-v1-ik2
UEK3                0               2.6.32-400.21.1     2.6.32-400.21.1       el5                 UEK-v1-ik3
UEK4                0               2.6.39-400.17.1     2.6.39-400.9999.9999  el6                 UEK-v2
UEK5                0               2.6.32-400.23       2.6.32-400.9999.9999  el5                 UEK-v1-ik4
UEK6                0               2.6.39-400.17.1     2.6.39-400.9999.9999  el5                 UEK-v2
UEK7                0               3.8.13-16           3.8.13-9999.9999.9999 el6                 UEK-v3
UEK8                0               3.8.13-35.3.1       3.8.13-9999.9999.9999 el7                 UEK-v3
UEK9                0               4.1.12-32           4.1.12-32.2.1         el6                 UEK-v4
TD                  0               2.6.32.54-0.23      2.6.32.54-0.23                            TD
TD2                 0               2.6.16.60-0.91      2.6.16.60-0.137                           TD
TD3                 0               2.6.32.54-0.35      2.6.32.54-0.79                            TD-ik2
# agent version -> agent signature mapping:
# RRR1P1: 2103713736
# RRR1P2: 2103713736
# RRR2: 2103713736
# RRR2P1: 2103713736
# RRR2P2: 2103713736, 28697893
# RRR2P3: 2350452553, 3553360080, 2481918936, 3384926936
# SR1: 2350452553, 3553360080, 2481918936, 3384926936
# SR2: 3766268762, 3686701036, 3542803736, 1954018875

