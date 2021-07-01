#!/usr/bin/env bash

source_self="source ./integration/load.sh"

db_name=db
db_redis=db_redis
dmsg_prog=dmsg
dmsgpty_prog=dmsgpty
dmsgdisc_prog=dmsg_disc

# tmux session: dmsg
function setup_vars() {
  mkdir -p ./integration/integration-configs
  for i in $(seq 100); do
    ./bin/dmsgpty-host confgen ./integration/integration-configs/dmsgpty-host-"$i".json
    perl -pe 's/dmsg.discovery.skywire.skycoin.com/localhost:9090/g' ./integration/integration-configs/dmsgpty-host-"$i".json >temp.json && mv temp.json ./integration/integration-configs/dmsgpty-host-"$i".json
    perl -pe s/dmsgpty/dmsgpty${i}/ ./integration/integration-configs/dmsgpty-host-"$i".json >temp.json && mv temp.json ./integration/integration-configs/dmsgpty-host-"$i".json
    alias dmsgpty${i}-host='./bin/dmsgpty-host -c ./integration/integration-configs/dmsgpty-host-"$i".json'
    alias dmsgpty${i}-cli='./bin/dmsgpty-cli --confpath ./integration/integration-configs/dmsgpty-host-"$i".json'
    export dmsg_srv${i}=dmsg_srv${i}
  done
}

# func_print prepends function name to echoed message.
function func_print() {
  echo "load.sh [${FUNCNAME[1]}] $*"
}


function catch_ec() {
  if [[ $1 -ne 0 ]]; then
    echo "last command exited with non-zero exit code: $1"
    exit $1
  fi
}

# has_session returns whether a tmux session of given name exists or not.
# Input 1: session name.
function has_session() {
  if [[ $# -ne 1 ]]; then
    func_print "expected 1 arg(s), got $#" 1>&2
    exit 1
  fi

  session_name=$1

  [[ $(tmux ls | grep "${session_name}") == "${session_name}:"* ]]
}

# send_to_all_windows sends a command to all windows of a given tmux session.
# Input 1: tmux session name.
function send_to_all_windows() {
  if [[ $# -ne 2 ]]; then
    func_print "expected 2 arg(s), got $#" 1>&2
    exit 1
  fi

  session_name=$1
  cmd_name=$2

  for W_NAME in $(tmux list-windows -F '#W' -t "${session_name}"); do
    tmux send-keys -t "${W_NAME}" "${cmd_name}" C-m
  done
}

# is_redis_running returns whether redis is running.
function is_redis_running() {
  [[ "$(redis-cli ping 2>&1)" == "PONG" ]]
}

function init_redis() {
  if is_redis_running; then
    func_print "redis-server already running, nothing to be done"
    return 0
  fi

  if has_session "${db}"; then
    func_print "tmux session ${db} will be killed before restarting"
    tmux kill-session -t "${db}"
  fi

  tmux new -d -s "${db}"
  tmux new-window -a -t "${db}" -n ${db_redis}
  tmux send-keys -t ${db_redis} 'redis-server' C-m

  # Wait until redis is up and running
  for i in {1..5}; do
    sleep 0.5
    if is_redis_running; then
      func_print "attempt $i: redis-server started"
      tmux select-window -t bash
      return 0
    fi
    func_print "attempt $i: redis-server not started, checking again in 0.5s..."
  done

  func_print "failed to start redis-server"
  exit 1
}

# stop_redis stops redis and it's associated tmux session/window.
function stop_redis() {
  if [[ "$(redis-cli ping 2>&1)" != "PONG" ]]; then
    func_print "redis-server is not running, nothing to be done."
  elif tmux kill-session -t "${db}"; then
    killall redis-server
  fi
}

function attach_redis() {
  tmux attach -t "${db}"
}

function init_dmsg() {
  if has_session "${db}"; then
    func_print "Session already running, nothing to be done here."
    return 0
  fi

  # dmsg session depends on redis.
  init_redis

  func_print "Creating ${dmsg_prog} tmux session..."
  tmux new -d -s ${dmsg_prog}
  tmux new-window -a -t ${dmsg_prog} -n ${dmsgdisc_prog}
  tmux new-window -a -t ${dmsg_prog} -n "bash"
  tmux send-keys -t bash "bash" C-m

  func_print "Running ${dmsgdisc_prog}..."
  tmux send-keys -t ${dmsgdisc_prog} './bin/dmsg-discovery -t' C-m
  catch_ec $?

  send_to_all_windows ${dmsg_prog} "${source_self}"

  for i in $(seq 2); do
    tmux new-window -a -t ${dmsg_prog} -n dmsg_srv${i}
    func_print "Running dmsg_srv${i}..."
    tmux send-keys -t "dmsg_srv${i}" "./bin/dmsg-server ./integration/configs/dmsgserver${i}.json" C-m
    catch_ec $?
  done

  sleep 1
  func_print "${dmsg_prog} session started successfully."
  tmux select-window -t bash
}

function stop_dmsg() {
  tmux kill-session -t ${dmsg_prog}
  return 0
}

function attach_dmsg() {
  tmux attach -t ${dmsg_prog}
}

function init_dmsgpty() {
  if has_session ${dmsgpty_prog}; then
    func_print "Session already running, nothing to be done here."
    return 0
  fi

  # dmsgpty session depends on dmsg.
  init_dmsg

  func_print "Creating ${dmsgpty_prog} tmux session..."
  tmux new -d -s ${dmsgpty_prog}
  tmux send-keys -t bash "bash" C-m

  for i in $(seq 100); do
    tmux new-window -a -t ${dmsgpty_prog} -n dmsgpty_h${i}
    func_print "Running dmsgpty_h${i}..."
    tmux send-keys -t dmsgpty_h${i} "${source_self} && dmsgpty${i}-host" C-m
    pk=$(awk '1' ./integration/integration-configs/dmsgpty-host-${i}.json | jq -r .pk)
    tmux send-keys -t bash "dmsgpty${i+1}-cli whitelist-add ${pk}" C-m
    catch_ec $?
  done
  send_to_all_windows ${dmsgpty_prog} "${source_self}"

  sleep 1
  for i in $(seq 100 -1 1); do
    pk=$(awk '1' ./integration/integration-configs/dmsgpty-host${i}.json | jq -r .pk)
    tmux send-keys -t bash "dmsgpty${i}-cli whitelist-add ${pk} && print_dmsgpty_help" C-m
  done

  func_print "${dmsgpty_prog} session started successfully."
  tmux select-window -t bash
}

function stop_dmsgpty() {
  tmux kill-session -t ${dmsgpty_prog}
  return 0
}

function attach_dmsgpty() {
  tmux attach -t ${dmsgpty_prog}
}
