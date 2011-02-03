#! /bin/bash

if [ -z "$1" ]
then
   echo $0: usage: $0 filename
   exit 3
fi
if [ ! -r $1 ]
then
   echo $0: I see no $q file here.
   exit 1
fi
if [ ! -w . ]
then
   echo $0: I will not be able to delte $1 for you.
   echo So I give up.
   exit 2
fi

tail $1
exit 0
