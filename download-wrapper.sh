#!/bin/bash

# This is a wrapper around wget which doesn't do anything if the file
# already exists

function check_file ()
{
    while test "$#" -ge 2; do
        if test "$1" = "-o" -o "$1" = "-O"; then
            if test -f "$2"; then
                echo "$2 already downloaded";
                exit 0;
            fi;
        fi;

        shift;
    done
}

check_file "$@";

exec wget "$@";
