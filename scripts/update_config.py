import yaml
import os
import sys

def update_secrets(secrets_file, output_file, db_url, audit_db_url, search_db_url, redis_url, analytic_redis_url, filter_keys=None):
    with open(secrets_file, 'r') as f:
        doc = yaml.safe_load(f)

    secrets = doc.get('secrets', [])
    
    # Helper to update or append a secret
    def update_or_append(key, data):
        found = False
        for s in secrets:
            if s['key'] == key:
                s['data'] = data
                found = True
                break
        if not found:
            secrets.append({'key': key, 'data': data})

    # Update DB configs
    update_or_append('db', {'database_url': db_url, 'database_schema': 'public'})
    update_or_append('audit.db', {'database_url': audit_db_url, 'database_schema': 'audit'})
    update_or_append('images.db', {'database_url': db_url, 'database_schema': 'public'})
    update_or_append('search.db', {'database_url': search_db_url, 'database_schema': 'search'})
    
    # Update Redis configs
    update_or_append('redis', {'redis_url': redis_url})
    update_or_append('analytic.redis', {'redis_url': analytic_redis_url})

    # Filter keys if requested (allow-list)
    if filter_keys:
        secrets = [s for s in secrets if s['key'] in filter_keys]

    doc['secrets'] = secrets

    with open(output_file, 'w') as f:
        yaml.dump(doc, f, default_flow_style=False)

if __name__ == "__main__":
    if len(sys.argv) < 8:
        print("Usage: update_config.py <input_file> <output_file> <db_url> <audit_db_url> <search_db_url> <redis_url> <analytic_redis_url> [filter_keys_comma_separated]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    db_url = sys.argv[3]
    audit_db_url = sys.argv[4]
    search_db_url = sys.argv[5]
    redis_url = sys.argv[6]
    analytic_redis_url = sys.argv[7]
    
    filter_keys = None
    if len(sys.argv) > 8:
        filter_keys = sys.argv[8].split(',')

    update_secrets(input_file, output_file, db_url, audit_db_url, search_db_url, redis_url, analytic_redis_url, filter_keys)
