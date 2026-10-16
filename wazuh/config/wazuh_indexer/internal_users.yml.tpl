---
# This is the internal user database
# The hash value is a bcrypt hash and can be generated with plugin/tools/hash.sh

_meta:
  type: "internalusers"
  config_version: 2

# Define your internal users here

## Rendered by scripts/render-users.sh; hashes below are placeholders

admin:
  hash: "__ADMIN_HASH__"
  reserved: true
  backend_roles:
  - "admin"
  description: "Demo admin user"

kibanaserver:
  hash: "__KIBANA_HASH__"
  reserved: true
  description: "Demo kibanaserver user"
