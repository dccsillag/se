#!/bin/sh -x

[ -z "$PREFIX" ] && {
    if [ "$EUID" -eq 0 ]
    then
        PREFIX=/usr
    else
        PREFIX="$HOME/.local"
    fi
}

cp se.sh "$PREFIX/bin/se"
