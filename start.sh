#!/bin/bash
# Start the first process
./readsb.sh &

# Start the second process
./wingbits.sh &

# Wait for any process to exit
wait -n

# Exit with status of process that exited first
exit $?
