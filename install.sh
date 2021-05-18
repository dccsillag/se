#!/bin/sh -x

[ -z "$PREFIX" ] && {
    if [ "$(id -u)" -eq 0 ]
    then
        PREFIX=/usr
    else
        PREFIX="$HOME/.local"
    fi
}

cp se.sh "$PREFIX/bin/se"
