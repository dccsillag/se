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
}

ensure_session_is_finished() {
    ensure_session_exists "$1"
    is_running "$1" && {
        echo "Session is still running: $1" 1>&2
        exit 1
    }
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
                printf "%3d  $(tput bold)[running] %s$(tput sgr0)\n" "$id" "$(cat "$sess/command.txt")"
                printf "     %s\n" "$(cat "$sess/starttime.txt")"
            else
                exitcode="$(cat "$sess/exitcode.txt")"
                if [ "$exitcode" -eq 0 ]
                then
                    label="done"
                    color=2
                else
                    label="fail:$(printf "%3d" "$exitcode")"
                    color=4
                fi
                printf "%3d  $(tput bold)$(tput setf $color)[$label]$(tput sgr0)$(tput bold) %s$(tput sgr0)\n" "$id" "$(cat "$sess/command.txt")"
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
    -d) ensure_session_is_finished "$2"
        sess="$(get_session "$2")"
        echo "$(tput bold)Are you sure you want to delete this session?$(tput sgr0)"
        echo "  $(tput bold)COMMAND:$(tput sgr0) $(cat "$sess/command.txt")"
        echo "  $(tput bold)STARTED RUNNING:$(tput sgr0)  $(cat "$sess/starttime.txt")"
        echo "  $(tput bold)FINISHED RUNNING:$(tput sgr0) $(cat "$sess/endtime.txt")"
        echo
        printf '[yn] '
        read -r yn
        case "$yn" in
            [Yy]*)  echo "Deleting session '$2'" ;;
            [Nn]*)  echo "Aborting."; exit 0 ;;
            *)      echo "Answer was not 'yes' nor 'no'; aborting"; exit 1 ;;
        esac

        set -x
        rm -rf "$sess"
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

        echo "Running in the background."
        echo "  COMMAND: $*"
        echo "  HOST: $(hostname)"
        echo "  ID: $id"
        ;;
esac
