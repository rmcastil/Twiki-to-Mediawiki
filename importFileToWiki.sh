#! /bin/bash
prefix=$1

while [ ! -z "$2" ]
do

	file=${2##*/}

 	php importTextFile.php --title "$prefix:$file" --nooverwrite $2
	shift
done
exit 0
