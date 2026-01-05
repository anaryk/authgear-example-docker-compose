import yaml
import sys
import os

def get_env_secrets():
    # Helper to construct the secrets list from env vars
    return [
        {
            'key': 'db',
            'data': {
                'database_schema': os.environ.get('DATABASE_SCHEMA', 'public'),
                'database_url': os.environ.get('DATABASE_URL')
            }
        },
        {
            'key': 'audit.db',
            'data': {
                'database_schema': os.environ.get('AUDIT_DATABASE_SCHEMA', 'public'),
                'database_url': os.environ.get('AUDIT_DATABASE_URL')
            }
        },
        {
            'key': 'images.db',
            'data': {
                'database_schema': os.environ.get('DATABASE_SCHEMA', 'public'),
                'database_url': os.environ.get('DATABASE_URL')
            }
        },
        {
            'key': 'search.db',
            'data': {
                'database_schema': os.environ.get('SEARCH_DATABASE_SCHEMA', 'public'),
                'database_url': os.environ.get('SEARCH_DATABASE_URL')
            }
        },
        {
            'key': 'redis',
            'data': {
                'redis_url': os.environ.get('REDIS_URL')
            }
        },
        {
            'key': 'analytic.redis',
            'data': {
                'redis_url': os.environ.get('ANALYTIC_REDIS_URL')
            }
        }
    ]

def merge_main(main_file):
    if os.path.exists(main_file):
        with open(main_file, 'r') as f:
            doc = yaml.safe_load(f) or {}
    else:
        doc = {}

    if 'secrets' not in doc:
        doc['secrets'] = []

    new_secrets = get_env_secrets()
    
    # Update or append
    for ns in new_secrets:
        found = False
        for i, s in enumerate(doc['secrets']):
            if s['key'] == ns['key']:
                doc['secrets'][i] = ns
                found = True
                break
        if not found:
            doc['secrets'].append(ns)

    with open(main_file, 'w') as f:
        yaml.dump(doc, f, default_flow_style=False)
    print(f"Updated {main_file}")

def create_images_config(main_file, output_file):
    # Secrets that must be copied from the main generated config
    # The images service requires these core secrets to initialize
    REQUIRED_FROM_MAIN = ['admin-api.auth', 'oauth', 'csrf']
    
    # Secrets that we construct from environment variables
    # We include images.db as well since it's specific to this service
    REQUIRED_FROM_ENV = ['db', 'redis', 'images.db']

    filtered_secrets = []

    # 1. Get secrets from main config
    if os.path.exists(main_file):
        with open(main_file, 'r') as f:
            doc = yaml.safe_load(f) or {}
            for s in doc.get('secrets', []):
                if s['key'] in REQUIRED_FROM_MAIN:
                    filtered_secrets.append(s)
    
    # 2. Get secrets from env
    env_secrets = get_env_secrets()
    for s in env_secrets:
        if s['key'] in REQUIRED_FROM_ENV:
            filtered_secrets.append(s)

    output_doc = {'secrets': filtered_secrets}
    
    with open(output_file, 'w') as f:
        yaml.dump(output_doc, f, default_flow_style=False)
    print(f"Created {output_file}")

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == 'merge_main':
        merge_main(sys.argv[2])
    elif mode == 'create_images':
        create_images_config(sys.argv[2], sys.argv[3])
    else:
        print(f"Unknown mode: {mode}")
        sys.exit(1)
