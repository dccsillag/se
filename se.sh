#!/bin/sh

is_number() {
    echo "$1" | head -1 | grep '^[0-9]\+$' > /dev/null
    return $?
}

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
    find "$ROOTDIR" -maxdepth 1 -type d -name "$(hostname)-*"
}

session_exists() {
    [ -d "$ROOTDIR/$(hostname)-$1" ]
}

get_session() {
    session_exists "$1" || {
        echo "No such session: $1" 1>&2
        exit 1
    }

    echo "$ROOTDIR/$(hostname)-$1"
}

sess_id() {
    basename "$1" | sed "s/^.\+-\([0-9]\+\)$/\1/"
}

for sess in $(list_sessions)
do
    [ -f "$sess/pid" ] || continue
    ( kill -0 "$(cat "$sess/pid")" 2> /dev/null ) || rm "$sess/pid" "$sess/run.sh"
done

is_number "$1" && {
    echo "WARNING: The usage \`se <NUMBER>\` is deprecated and now has no meaning."
    echo "         Use \`se -v $1\` instead."
    exit 1
}

case "$1" in
    -l) for sess in $(list_sessions)
        do
            if [ -f "$sess/pid" ]
            then
                echo "$(sess_id "$sess")\t[running] $(cat "$sess/command.txt")"
                echo "\t$(cat "$sess/starttime.txt")"
            else
                echo "$(sess_id "$sess")\t[done] $(cat "$sess/command.txt")"
                echo "\t$(cat "$sess/starttime.txt") -- $(cat "$sess/endtime.txt")"
            fi
        done
        ;;
    -v) if [ -z "$3" ]
        then
            clear -x
            "$0" -v "$2" tail -f
        else
            f="$(get_session "$2")/stdout.txt"
            shift 2
            "$@" "$f"
        fi
        ;;
    -d) sess="$(get_session "$2")"
        [ -f "$sess/pid" ] && {
            echo "Session is running, and thus cannot be deleted: '$2'."
            exit 1
        }
        echo "Are you sure you want to delete this session?"
        echo "  COMMAND: $(cat "$sess/command.txt")"
        echo "  STARTED RUNNING:  $(cat "$sess/starttime.txt")"
        echo "  FINISHED RUNNING: $(cat "$sess/endtime.txt")"
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
    -c) kill -2  "$(cat "$ROOTDIR/$(get_id "$2")/pid")" ;;
    -t) kill -15 "$(cat "$ROOTDIR/$(get_id "$2")/pid")" ;;
    -K) kill -9  "$(cat "$ROOTDIR/$(get_id "$2")/pid")" ;;
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

        # Create shell script to run with nohup
        echo "date > '$sessdir/starttime.txt'" >> "$scriptfile"
        for arg in "$@"
        do
            printf "'%s' " "$(echo "$arg" | sed s/\'/\'\\\\\'\'/g)"
        done >> "$scriptfile"
        echo >> "$scriptfile"
        echo "date > '$sessdir/endtime.txt'" >> "$scriptfile"
        chmod +x "$scriptfile"

        # Run with nohup
        nohup "$scriptfile" > "$outfile" 2>&1 &
        pid="$!"
        echo "$pid" > "$pidfile"
        echo "$*" > "$cmdfile"

        echo "Running in the background."
        echo "  COMMAND: $*"
        echo "  HOST: $(hostname)"
        echo "  PID: $pid"
        echo "  ID: $id"
        ;;
esac
