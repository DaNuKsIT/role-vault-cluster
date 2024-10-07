#!/bin/bash
set -e

script_name="$(basename "$0")"

function stop {
  local vault_node_name=$1

  service_count=$(pgrep -f {{ vault_dir }}/config-$vault_node_name | wc -l | tr -d '[:space:]')

  printf "\n%s" \
    "Found $service_count Vault service(s) matching that name"

  if [ "$service_count" != "0" ] ; then
    printf "\n%s" \
      "[$vault_node_name] stopping" \
      ""

    pkill -f "{{ vault_dir }}/config-$vault_node_name"
  fi
}

function start {
  local vault_node_name=$1

  local vault_config_file={{ vault_dir }}/config-$vault_node_name.hcl
  local vault_log_file={{ vault_dir }}/$vault_node_name.log

  printf "\n%s" \
    "[$vault_node_name] starting Vault server @ $VAULT_ADDR" \
    ""

  if [[ "$vault_node_name" != "init" ]] ; then
    if [[ -e "{{ vault_dir }}/root_token" ]] ; then
      VAULT_TOKEN=$(cat "{{ vault_dir }}"/root_token)

      printf "\n%s" \
        "Using [init] root token ($VAULT_TOKEN) to retrieve transit key for auto-unseal"
      printf "\n"
    fi
  fi

  VAULT_TOKEN=$VAULT_TOKEN vault server -log-level=trace -config "$vault_config_file" > "$vault_log_file" 2>&1 &
}

function setup_init {
  start "init"
  sleep 5

  printf "\n%s" \
    "[init] initializing and capturing the unseal key and root token" \
    ""

  INIT_RESPONSE=$(vault operator init -format=json -key-shares 5 -key-threshold 2)

  UNSEAL_KEYS=$(echo "$INIT_RESPONSE" | jq -r .unseal_keys_b64)
  VAULT_TOKEN=$(echo "$INIT_RESPONSE" | jq -r .root_token)

  echo $UNSEAL_KEYS | jq -r .[0] > {{ vault_dir }}/unseal_key1
  echo $UNSEAL_KEYS | jq -r .[1] > {{ vault_dir }}/unseal_key2
  echo $UNSEAL_KEYS | jq -r .[2] > {{ vault_dir }}/unseal_key3
  echo $UNSEAL_KEYS | jq -r .[3] > {{ vault_dir }}/unseal_key4
  echo $UNSEAL_KEYS | jq -r .[4] > {{ vault_dir }}/unseal_key5

  echo $VAULT_TOKEN > {{ vault_dir }}/root_token

  printf "\n%s" \
    "[init] Root token: $VAULT_TOKEN" \
    ""

  printf "\n%s" \
    "[init] unsealing and logging in" \
    ""

  vault operator unseal $(cat {{ vault_dir }}/unseal_key1)
  vault operator unseal $(cat {{ vault_dir }}/unseal_key2)

  vault login "$VAULT_TOKEN"

  printf "\n%s" \
    "[init] enabling the transit secret engine and creating a key to auto-unseal vault cluster" \
    ""

  vault secrets enable transit
  vault write -f transit/keys/unseal_key
}

function setup_master {
  start "master"
  sleep 5

  printf "\n%s" \
    "[master] initializing and capturing the recovery key and root token" \
    ""

  INIT_RESPONSE2=$(vault operator init -format=json -recovery-shares 5 -recovery-threshold 2)

  RECOVERY_KEYS=$(echo "$INIT_RESPONSE2" | jq -r .recovery_keys_b64)
  VAULT_TOKEN2=$(echo "$INIT_RESPONSE2" | jq -r .root_token)

  echo $RECOVERY_KEYS | jq -r .[0] > {{ vault_dir }}/recovery_key1
  echo $RECOVERY_KEYS | jq -r .[1] > {{ vault_dir }}/recovery_key2
  echo $RECOVERY_KEYS | jq -r .[2] > {{ vault_dir }}/recovery_key3
  echo $RECOVERY_KEYS | jq -r .[3] > {{ vault_dir }}/recovery_key4
  echo $RECOVERY_KEYS | jq -r .[4] > {{ vault_dir }}/recovery_key5
  echo "$VAULT_TOKEN2" > {{ vault_dir }}/master_token

  printf "\n%s" \
    "[master] Root token: $VAULT_TOKEN2" \
    ""

  printf "\n%s" \
    "[master] waiting to finish post-unseal setup (15 seconds)" \
    ""

  sleep 15

  printf "\n%s" \
    "[master] logging in and enabling the KV secrets engine" \
    ""

  vault login "$VAULT_TOKEN2"
  vault secrets enable -path=kv kv-v2
}

function status {
  vault status
  VAULT_TOKEN=$(cat "{{ vault_dir }}"/master_token) vault operator raft list-peers
}

function clean {

  for key_file in {{ vault_dir }}/unseal_key1 {{ vault_dir }}/unseal_key2 {{ vault_dir }}/unseal_key3  {{ vault_dir }}/unseal_key4  {{ vault_dir }}/unseal_key5  {{ vault_dir }}/recovery_key1  {{ vault_dir }}/recovery_key2  {{ vault_dir }}/recovery_key3 {{ vault_dir }}/recovery_key4  {{ vault_dir }}/recovery_key5; do
    if [[ -f "$key_file" ]] ; then
      printf "\n%s" \
        "Removing key $key_file"

      rm "$key_file"
    fi
  done

  for token_file in {{ vault_dir }}/root_token {{ vault_dir }}/master_token ; do
    if [[ -f "$token_file" ]] ; then
      printf "\n%s" \
        "Removing token $token_file"

      rm "$token_file"
    fi
  done

  for log_file in {{ vault_dir }}/init.log {{ vault_dir }}/master.log {{ vault_dir }}/worker.log ; do
    if [[ -f "$log_file" ]] ; then
      printf "\n%s" \
        "Removing log file $log_file"

      rm "$log_file"
    fi
  done

  for database_dir in {{ vault_dir }}/data {{ vault_dir }}/data-init; do
    if [[ -d "$database_dir" ]] ; then
      printf "\n%s" \
        "Removing database in $database_dir"

      rm -rf $database_dir/*
    fi
  done

  unset VAULT_TOKEN

  printf "\n%s" \
    "Clean complete" \
    ""
}


function setup {
  case "$1" in
    init)
      setup_init
      ;;
    master)
      setup_master
      ;;
    worker)
      start "worker" 
      sleep 5
      VAULT_TOKEN=$(cat {{ vault_dir }}/master_token) vault operator raft join https://{{ hostname_master_server }}:8200
      ;;
  esac
}

function startup {
  case "$1" in
    init)
      start init
      sleep 10
      vault operator unseal $(cat {{ vault_dir }}/unseal_key1)
      vault operator unseal $(cat {{ vault_dir }}/unseal_key2)
      vault login $(cat {{ vault_dir }}/root_token)
      ;;
    master)
      start master
      ;;
    worker)
      start worker
      ;;
  esac
}

case "$1" in
  create)
    shift ;
    create "$@"
    ;;
  setup)
    shift ;
    setup "$@"
    ;;
  status)
    status
    ;;
  start)
    shift ;
    start "$@"
    ;;
  stop)
    shift ;
    stop "$@"
    ;;
  clean)
    shift ;
    stop "$@"
    clean
    ;;
  startup)
    shift ;
    startup "$@"
    ;;
esac
