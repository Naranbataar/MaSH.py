#!/bin/bash
MASH_WS_PID="$$"
export MASH_WS_PID

PIPE='.ws_pipe'
mkfifo $PIPE
exec 3<> ${PIPE}
ACKF='.ws_lastack'
[ -f $ACKF ] || touch $ACKF
SEQF='.ws_seqf'
[ -f $SEQF ] || touch $SEQF
SESF='.ws_sessionid'
[ -f $SESF ] || touch $SESF

clean(){
	rm $PIPE
	kill 0
}
trap clean EXIT

SENT=0
gateway(){
	MINIMAL=$(( $SENT + 500 ))
	NOW=$(( $(date +%s%N)/1000000 ))
   	echo "{\"op\": $1, \"d\": $2}" | jq -cM >&3
	if [ $NOW -lt $MINIMAL ]; then
		sleep "$(( $MINIMAL - $NOW ))"
	fi
}

heartbeat(){
	LACK="0"
	WAIT=15
	INTERVAL=$(awk -v m=$m "BEGIN { print ($1 / 1000) - $WAIT }")
	while true; do
		SEQ=$(cat "$SEQF")
		gateway 1 "$SEQ" >&3
		ACK=$(cat "$ACKF")

		sleep "$WAIT"
		if [ $LACK == $ACK ]; then
			pkill -9 $MASH_WS_PID
			exit 1	
		fi

		sleep "$INTERVAL"
		LACK=$ACK
	done
}

while read PAYLOAD; do
	OP=$(echo "$PAYLOAD" | jq -r '.op')
	DATA=$(echo "$PAYLOAD" | jq '.d')

	case $OP in
	0)
	echo "$(echo "$PAYLOAD" | jq -r '.s')" > $SEQF
	echo "$PAYLOAD" ;;	
	1)
	echo "$(echo "$PAYLOAD" | jq '.d' | jq '.session_id')" > $SESF ;;
	7)
	exit 1 ;;
	9)
	rm $SESF
	exit 1 ;;
	10)
	INTERVAL=$(echo "$DATA" | jq '.heartbeat_interval')
	heartbeat "$INTERVAL" &

	if [ -f "$SESF" ]; then
		gateway 2 "{\"token\": \"$MASH_TOKEN\", \"properties\": {\"\$os\": \"linux\",\"\$browser\": \"mash\",\"\$device\": \"mash\"}}"
	else
		SEQ=$(cat $SEQF); SES=$(cat $SESF)
		gateway 6 "{\"token\": \"$MASH_TOKEN\", \"session_id\": \"$SES\", \"seq\": $SEQ}"
	fi ;;
	11)
	echo "$(( $(date +%s%N)/1000000 ))" > $ACKF ;;
	esac	
done < <(websocat -tnE "wss://gateway.discord.gg/?v=6&encoding=json" < $PIPE)