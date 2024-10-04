storage "inmem" {}

listener "tcp" {
   address = "{{ inventory_hostname }}:8200"
   tls_disable = false 
   tls_cert_file = "/etc/ssl/keys/cert.crt"
   tls_key_file  = "/etc/ssl/keys/key.key"
}

ui = true
disable_mlock = true
