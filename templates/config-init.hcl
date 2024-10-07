storage "file" {
  path = "/etc/vault.d/data-init"
}

listener "tcp" {
   address = "{{ inventory_hostname }}:8200"
   tls_disable = false 
   tls_cert_file = "{{ TLS_CERT_FILE }}"
   tls_key_file  = "{{ TLS_KEY_FILE }}"
}

ui = true
disable_mlock = true
