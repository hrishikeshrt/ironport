#!/bin/sh

trap logout 1 2 3 9 15

log() {
 export ts="`date +[%b\ %e\ %H:%M:%S]`"
 echo $ts $@ >> ${LOGFILE}
 logger -t IronPort $@
}

logout() {
    curl -s --form "logout='Log Out Now'" $refurl  > /dev/null 2> /dev/null
    log "Logged out."
    rm $PIDFILE
    exit 0
}
# script (daemon) name
NAME=$(basename $0)

# check if log file is in place and of adequate size
LOGFILE="/var/log/iitk-ironport.log"
[ -f $LOGFILE ] || touch $LOGFILE
[ -w $LOGFILE ] || LOGFILE="/tmp/`whoami`-ironport.log"

LOGSIZE=$(du $LOGFILE | awk '{ print $1 }')
[ $LOGSIZE -lt 1024 ]  || ( mv ${LOGFILE} ${LOGFILE}.old && touch $LOGFILE )

# get pid
oldPID=""
myPID=`echo $$`

PIDDIR="/var/run/"
[ -w ${PIDDIR} ] || PIDDIR="${HOME}"
PIDFILE="${PIDDIR}/${NAME}.pid"

[ ! -f ${PIDFILE} ] || oldPID=$(cat $PIDFILE)
[ -z "$oldPID" ] || ((log "Error: Daemone with PID ${oldPID} already running. ($myPID)") && exit 1)
echo ${myPID} > ${PIDFILE}

log "Starting ironport-authentication daemon .. ($myPID)"

# login details
CONFIG="$HOME/.iitk-config"
[ -f $CONFIG ] || CONFIG="/usr/share/iitk-auth/config"
[ -f $CONFIG ] || (logger -sit IronPort "No config file found." && exit 1)

export user="`sed -n '1 p' ${CONFIG}`"
export pass="`sed -n '2 p' ${CONFIG}`"
export ip="172.22.1.1" # any ironport ip

([ -z "$user" ] || [ -z "$pass" ] || [ -z "$ip" ]) &&  (logger -sit IronPort "Invalid config." && exit 1)

export refurl='http://authenticate.iitk.ac.in/netaccess/connstatus.html'
export authurl='http://authenticate.iitk.ac.in/netaccess/loginuser.html'
export authurl1='https://ironport1.iitk.ac.in/B0001D0000N0000N0000F0000S0000R0004/'${ip}'/http://www.google.co.in/'
export authurl2='https://ironport2.iitk.ac.in/B0001D0000N0000N0000F0000S0000R0004/'${ip}'/http://www.google.co.in/'

export loop_every=4

while true; do
    refresh=${loop_every}

    # Cisco Authentication
    curl -s --form "sid=0" --form "login='Log In Now'" $refurl  > /dev/null 2> /dev/null
    sleep 1

    cisco=$(
        curl -s --form "username=$user" --form "password=$pass" --form "Login=Continue" --referer $refurl $authurl --stderr /dev/null
    )

    if [ "`echo $cisco | grep 'You are logged in'`" ]; then
        log "Auth succesful."
    else 
        if [ "`echo $cisco | grep "Credentials Rejected"`" ]; then
            log "Error: Credentials rejected. (auth)"
        else
            log "Error: Something went wrong. (auth)"
            refresh=1
        fi
    fi 
    sleep 1

    # HTTPS Authentication
    auth1=$(
        curl -s --insecure --user "${user}:${pass}" $authurl1 --stderr /dev/null
    )
    auth2=$(
        curl -s --insecure --user "${user}:${pass}" $authurl2 --stderr /dev/null
    )
    if [ "`echo $auth1 | grep AUTH_REQUIRED`" ]; then
        log "Error: Auth1 failed."
        refresh=1
    else
        if [ "`echo $auth1 | grep 'request is being redirected'`" ]; then
            log "Auth1 successful."
        else
            log "Error: `echo $auth1 | grep 'Notification: ' | grep -v '<title>'` (auth1)"
        fi
    fi

    if [ "`echo $auth2 | grep AUTH_REQUIRED`" ]; then
        log "Error: Auth2 failed."
        refresh=1
    else
        if [ "`echo $auth2 | grep 'request is being redirected'`" ]; then
            log "Auth2 successful."
        else
            log "Error: `echo $auth2 | grep 'Notification: ' | grep -v '<title>'` (auth2)"
        fi
    fi

    #  export futuredate="`date -D '%s' +'[%H:%M:%S]' -d $((\`date +%s\` + ${refresh}*60))`"
    export futuredate="`date +[%H:%M:%S] --date="${refresh}min"`"
    log "Refreshing at '${futuredate}'"
    sleep $(( ${refresh} * 60 ))
done
