#!/bin/sh

[ "$#" -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] && {
    echo "Usage:"
    echo "  $0 -l        # list sessions"
    echo "  $0 <COMMAND> # create a session"
    echo "  $0 -v <ID>   # view a session"
    echo "  $0 -d <ID>   # delete a session"
    echo "  $0 -c <ID>   # cancel a session (SIGINT)"
    echo "  $0 -t <ID>   # terminate a session (SIGTERM)"
    echo "  $0 -K <ID>   # kill -9 a session (SIGKILL)"
    exit 0
}

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_RED='\033[31m'
C_GREEN='\033[32m'

ROOTDIR="$HOME/.local/share/se"
mkdir -p "$ROOTDIR"

list_sessions() {
    ls "$ROOTDIR" -r --sort=time | grep "$(hostname)-*" | sed "s/$(hostname)-\\(.\\+\\)/\\1/"
}

get_session() {
    echo "$ROOTDIR/$(hostname)-$1"
}

session_exists() {
    [ -d "$(get_session "$1")" ]
}

is_running() {
    session_exists "$1" && [ -f "$(get_session "$1")/pid" ]
}

ensure_session_exists() {
    session_exists "$1" || {
        echo "Session does not exist: $1" 1>&2
        exit 1
    }
}

ensure_session_is_running() {
    ensure_session_exists "$1"
    is_running "$1" || {
        echo "Session has already finished: $1" 1>&2
        exit 1
    }
    true
}

ensure_session_is_finished() {
    ensure_session_exists "$1"
    is_running "$1" && {
        echo "Session is still running: $1" 1>&2
        exit 1
    }
    true
}

for id in $(list_sessions)
do
    sess="$(get_session "$id")"
    [ -f "$sess/pid" ] || continue
    ( kill -0 "$(cat "$sess/pid")" 2> /dev/null ) || rm "$sess/pid" "$sess/run.sh"
done

case "$1" in
    -l) for id in $(list_sessions)
        do
            sess="$(get_session "$id")"
            if [ -f "$sess/pid" ]
            then
                printf "%3d  $C_BOLD[running] %s$C_RESET\n" "$id" "$(cat "$sess/command.txt")"
                printf "     %s\n" "$(cat "$sess/starttime.txt")"
            else
                exitcode="$(cat "$sess/exitcode.txt")"
                if [ "$exitcode" -eq 0 ]
                then
                    label="done"
                    color="$C_GREEN"
                else
                    label="fail:$(printf "%3d" "$exitcode")"
                    color="$C_RED"
                fi
                printf "%3d  $C_BOLD$color[$label]$C_RESET$C_BOLD %s$C_RESET\n" "$id" "$(cat "$sess/command.txt")"
                printf "     %s -- %s\n" "$(cat "$sess/starttime.txt")" "$(cat "$sess/endtime.txt")"
            fi
        done
        ;;
    -v) if [ -z "$3" ]
        then
            clear -x
            "$0" -v "$2" tail -f
        else
            ensure_session_exists "$2"
            f="$(get_session "$2")/stdout.txt"
            shift 2
            "$@" "$f"
        fi
        ;;
    -d) shift 1
        for id in "$@"
        do
            ( ensure_session_is_finished "$id" && rm -rf "$(get_session "$id")" )
        done
        ;;
    -c) ensure_session_is_running "$2" && kill -2  "$(cat "$(get_session "$2")/pid")" ;;
    -t) ensure_session_is_running "$2" && kill -15 "$(cat "$(get_session "$2")/pid")" ;;
    -K) ensure_session_is_running "$2" && kill -9  "$(cat "$(get_session "$2")/pid")" ;;
    -*) echo "Bad flag: $1. See \`se -h\`." ;;
    *)  # Get new ID
        id=0
        while session_exists "$id"
        do
            id=$((id+1))
        done

        # Setup session files
        sessdir="$ROOTDIR/$(hostname)-$id"
        mkdir -p "$sessdir"
        scriptfile="$sessdir/run.sh"
        outfile="$sessdir/stdout.txt"
        pidfile="$sessdir/pid"
        cmdfile="$sessdir/command.txt"
        starttimefile="$sessdir/starttime.txt"
        endtimefile="$sessdir/endtime.txt"
        exitcodefile="$sessdir/exitcode.txt"

        # Create shell script to run with nohup
        echo "date > '$starttimefile'" >> "$scriptfile"
        for arg in "$@"
        do
            printf "'%s' " "$(echo "$arg" | sed s/\'/\'\\\\\'\'/g)"
        done >> "$scriptfile"
        echo "&" >> "$scriptfile"
        echo "pid=\$!" >> "$scriptfile"
        echo "echo \$pid > '$pidfile'" >> "$scriptfile"
        echo "wait \$pid" >> "$scriptfile"
        echo "echo \$? > '$exitcodefile'" >> "$scriptfile"
        echo "date > '$endtimefile'" >> "$scriptfile"
        chmod +x "$scriptfile"

        # Run with nohup
        nohup "$scriptfile" > "$outfile" 2>&1 &
        echo "$*" > "$cmdfile"

        echo "Running in the background: $C_DIM$(hostname)-$C_BOLD$id$C_RESET"
        ;;
esac
