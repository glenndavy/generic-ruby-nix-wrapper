# Rails Application Service Module

This flake has been modified to support running Rails applications with Procfile-based role configuration as NixOS services.

## Key Features

### 1. Role-Based Execution

The module includes a `role` attribute that specifies which role from your Procfile to run:

```nix
services.rails-app = {
  role = "web";  # Run the 'web' role from Procfile
};
```

Common roles include:
- `web` - Web server (Puma, Unicorn, etc.)
- `worker` - Background job processor (Sidekiq, Resque, etc.)
- `scheduler` - Scheduled tasks (Clockwork, etc.)

### 2. Procfile Parsing

The module automatically reads and parses your Procfile to extract the command for the specified role (flake.nix:231-254). The parser:
- Reads the Procfile content
- Finds the line matching your role (e.g., `web: bundle exec puma`)
- Extracts the command after the colon
- Throws an error if the role isn't found

### 3. Custom Procfile Path

By default, the module looks for `./Procfile`, but you can specify an alternative file:

```nix
services.rails-app = {
  procfilePath = ./Procfile.production;
};
```

This is useful if you have different Procfiles for different environments.

## Configuration Options

### Required Options

- **`enable`** - Enable the Rails application service
- **`role`** - The role from Procfile to run (e.g., "web", "worker", "scheduler")
- **`workingDirectory`** - Path to your Rails application directory

### Optional Options

- **`package`** - The Rails application package to use (defaults to the flake's default package)
- **`procfilePath`** - Path to the Procfile (defaults to `./Procfile`)
- **`user`** - User account for the service (defaults to "rails")
- **`group`** - Group for the service (defaults to "rails")
- **`environment`** - Environment variables (defaults to production mode)
- **`extraServiceConfig`** - Additional systemd service configuration

## Usage Example

### Basic Configuration

```nix
{
  services.rails-app = {
    enable = true;
    role = "web";
    workingDirectory = /var/www/myapp;
  };
}
```

### Advanced Configuration

```nix
{
  services.rails-app = {
    enable = true;
    role = "web";
    workingDirectory = /var/www/myapp;

    # Use a different Procfile
    procfilePath = /var/www/myapp/Procfile.production;

    # Custom environment variables
    environment = {
      RAILS_ENV = "production";
      DATABASE_URL = "postgresql://user:pass@localhost/myapp_production";
      REDIS_URL = "redis://localhost:6379/0";
      SECRET_KEY_BASE = "your-secret-key-here";
      RAILS_LOG_TO_STDOUT = "true";
    };

    # Custom user/group
    user = "myapp";
    group = "myapp";

    # Additional systemd options
    extraServiceConfig = {
      LimitNOFILE = "65536";
      TimeoutStartSec = "600";
    };
  };
}
```

### Running Multiple Roles

You can run multiple roles from the same Procfile by defining multiple service configurations:

```nix
{
  # Web server
  services.rails-app = {
    enable = true;
    role = "web";
    workingDirectory = /var/www/myapp;
  };

  # Background worker (requires separate import or naming)
  # Note: You'll need to modify the module to support multiple instances
  # or import the module multiple times with different names
}
```

## Example Procfile

Your Procfile should follow the standard format:

```
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -C config/sidekiq.yml
scheduler: bundle exec clockwork config/schedule.rb
release: bundle exec rails db:migrate
```

Each line has the format: `role: command`

## Systemd Service

The module creates a systemd service named `rails-app-<role>` (e.g., `rails-app-web`).

### Service Features

- **Automatic restart** - Restarts on failure after 10 seconds
- **Network dependency** - Waits for network before starting
- **Security hardening**:
  - `NoNewPrivileges` - Prevents privilege escalation
  - `PrivateTmp` - Isolated /tmp directory
  - `ProtectSystem` - Read-only system directories
  - `ReadWritePaths` - Only working directory is writable

### Managing the Service

```bash
# Start the service
systemctl start rails-app-web

# Stop the service
systemctl stop rails-app-web

# Restart the service
systemctl restart rails-app-web

# View logs
journalctl -u rails-app-web -f

# Check status
systemctl status rails-app-web
```

## Environment Variables

The module sets sensible defaults for Rails applications:

```nix
environment = {
  RAILS_ENV = "production";
  RAILS_LOG_TO_STDOUT = "true";
  GEM_HOME = "${cfg.package}";
  GEM_PATH = "${cfg.package}";
};
```

You can override or add additional environment variables as needed.

## Security Considerations

1. **Secret Management** - Store sensitive values (SECRET_KEY_BASE, database passwords) securely using NixOS secrets management tools like agenix or sops-nix
2. **File Permissions** - The service runs with restricted permissions by default
3. **User Isolation** - Each Rails app runs under its own user account
4. **Read-only System** - System directories are protected from modification

## Troubleshooting

### Role not found error

If you see an error like "Role 'worker' not found in Procfile", check:
1. The role name matches exactly (case-sensitive)
2. The Procfile has the correct format (`role: command`)
3. The `procfilePath` points to the correct file

### Service fails to start

Check the logs for details:
```bash
journalctl -u rails-app-web -n 50
```

Common issues:
- Missing environment variables (DATABASE_URL, SECRET_KEY_BASE)
- Incorrect working directory
- Permission issues
- Missing dependencies in the gem environment
