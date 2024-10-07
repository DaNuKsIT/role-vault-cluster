storage "raft" {
   path    = "/etc/vault.d/data/"
   node_id = "{{ vault_id }}"
}

listener "tcp" {
   address = "{{ inventory_hostname }}:8200"
   cluster_address = "{{ inventory_hostname }}:8201"
   tls_disable = false
   tls_cert_file = "{{ TLS_CERT_FILE }}"
   tls_key_file  = "{{ TLS_KEY_FILE }}"
}

seal "transit" {
   address            = "https://{{ hostname_init_server }}:8200"
   disable_renewal    = "false"

   // Key configuration
   key_name           = "unseal_key"
   mount_path         = "transit/"
}

ui = true
disable_mlock = true
cluster_addr = "https://{{ inventory_hostname }}:8201"
