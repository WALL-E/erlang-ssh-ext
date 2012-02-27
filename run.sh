#!/bin/sh

usage()
{
	echo "Usage:"
	echo -e "\t$0 Command"
}

if [ $# -ne 1 ];then
	usage
	exit
fi

erlc agent.erl
erl -boot start_clean -noshell -smp +S 8 -s agent exec "$1"
