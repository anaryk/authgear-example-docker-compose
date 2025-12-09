# Contributing to Authgear Production Stack

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Focus on what is best for the community

## How to Contribute

### Reporting Bugs

1. Check if the issue already exists
2. Use the issue template
3. Provide detailed reproduction steps
4. Include logs and system information

### Suggesting Enhancements

1. Check existing feature requests
2. Describe the enhancement in detail
3. Explain why it would be useful
4. Provide examples if possible

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests: `./scripts/test.sh`
5. Ensure shellcheck passes: `shellcheck scripts/*.sh`
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## Development Guidelines

### Shell Scripts

- Use `#!/usr/bin/env bash` shebang
- Include `set -euo pipefail` for safety
- Pass shellcheck without errors
- Add comments for complex logic
- Use meaningful variable names
- Follow existing code style

### Documentation

- Update relevant documentation
- Add comments to complex configurations
- Include examples where helpful
- Keep README up to date

### Testing

All scripts must:
- Pass shellcheck validation
- Include error handling
- Be idempotent when possible
- Have meaningful log messages

### Commit Messages

- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit first line to 72 characters
- Reference issues and PRs when applicable

Example:
```
Add automated backup rotation script

- Implement retention policy
- Add compression support
- Include error notifications
Fixes #123
```

## Testing Changes

Before submitting:

```bash
# Run tests
./scripts/test.sh

# Validate with shellcheck
shellcheck scripts/*.sh

# Test Docker Compose
docker compose -f docker-compose.production.yml config

# Test Nginx config
docker run --rm -v $(pwd)/nginx.production.conf:/etc/nginx/nginx.conf:ro nginx:stable-alpine nginx -t
```

## Release Process

1. Update version in relevant files
2. Update CHANGELOG.md
3. Create git tag
4. Push to GitHub
5. Create release notes

## Questions?

Feel free to open an issue or discussion for any questions.

Thank you for contributing! 🎉
