# Project Structure

This document describes the organization of files in the WordPress on Azure Container Apps project.

## Root Directory

### Configuration Files

| File | Purpose | Notes |
|------|---------|-------|
| `azure.yaml` | Azure Developer CLI (azd) configuration | Defines project structure, hooks, and deployment settings |
| `.azdignore` | azd ignore patterns | Specifies files to exclude from azd packaging |
| `.env.template` | Environment variables template | Template for setting up azd environment variables |
| `.gitignore` | Git ignore patterns | Excludes sensitive data, build artifacts, and azd environments |

### Documentation

| File | Purpose |
|------|---------|
| `README.md` | Main project documentation with deployment instructions |
| `AZD_GUIDE.md` | Comprehensive Azure Developer CLI usage guide |
| `MIGRATION_GUIDE.md` | Guide for migrating from legacy scripts to azd |
| `ARCHITECTURE.md` | Detailed architecture and component documentation |
| `QUICK_REFERENCE.md` | Quick reference for common commands and operations |
| `TROUBLESHOOTING.md` | Troubleshooting guide for common issues |
| `PROJECT_STRUCTURE.md` | This file - project organization reference |

### Legacy Deployment (Backward Compatible)

| File | Purpose | Status |
|------|---------|--------|
| `main.bicep` | Legacy Bicep template location | ⚠️ Use `infra/main.bicep` instead |
| `nginx.conf` | Legacy nginx configuration location | ⚠️ Use `infra/nginx.conf` instead |
| `parameters.json` | Legacy parameter file | ⚠️ Use azd env variables instead |
| `parameters.dev.json` | Legacy dev parameter file | ⚠️ Use azd env variables instead |

**Note**: Legacy deployment scripts (`deploy.sh` and `deploy.ps1`) have been removed. All deployment now uses azd with automatic parameter validation through preprovision hooks.

## Infrastructure Directory (`infra/`)

Contains all infrastructure as code files for azd deployment.

### Main Files

| File | Purpose |
|------|---------|
| `main.bicep` | Main Bicep template with azd-specific outputs |
| `main.parameters.json` | azd parameter file with environment variable substitution |
| `nginx.conf` | Nginx reverse proxy configuration for WordPress |

### Hooks Directory (`infra/hooks/`)

Contains deployment lifecycle hooks. Platform-specific versions are automatically selected by azd.

| File | Purpose | Platform |
|------|---------|----------|
| `preprovision.sh` | Pre-provision parameter validation hook | Linux/macOS/WSL |
| `preprovision.ps1` | Pre-provision parameter validation hook | Windows PowerShell |
| `postprovision.sh` | Post-provision hook that uploads nginx.conf to NFS share | Linux/macOS/WSL |
| `postprovision.ps1` | Post-provision hook that uploads nginx.conf to NFS share | Windows PowerShell |

**Preprovision hooks** validate parameters before deployment:
- Environment name (1-9 chars, lowercase/numbers only)
- MySQL username (1-16 chars, alphanumeric only)
- MySQL password complexity (min 8 chars with upper/lower/number/special)
- Resource name length projections for all Azure resources

**Postprovision hooks** perform post-deployment tasks:
- Validate Azure CLI is installed and user is logged in
- Verify subscription matches azd target (if set)
- Upload nginx.conf to the NFS share

## Hidden Directories

| Directory | Purpose | Committed to Git? |
|-----------|---------|-------------------|
| `.git/` | Git version control | Yes |
| `.azure/` | azd environment configurations | No (gitignored) |

## Deployment Workflows

### Using Azure Developer CLI (azd) - Recommended

```
azure.yaml → points to infra/ directory
  ↓
infra/hooks/preprovision.sh/.ps1 → Validates all parameters
  ↓
infra/main.bicep → Deploys infrastructure
  ↓
infra/main.parameters.json → Parameters from environment variables
  ↓
infra/hooks/postprovision.sh/.ps1 → Uploads nginx.conf to storage
```

### Using Azure CLI Manually

```
Manual commands
  ↓
infra/main.bicep → Deploys infrastructure
  ↓
Manual upload → nginx.conf to storage
```

## Key Files for Modification

### To change infrastructure:
- **Primary**: `infra/main.bicep`
- **Legacy**: `main.bicep` (for backward compatibility)

### To change nginx configuration:
- **Primary**: `infra/nginx.conf`
- **Legacy**: `nginx.conf` (for backward compatibility)

### To change default parameters:
- **For azd**: Modify defaults in `infra/main.parameters.json`
- **For legacy**: Modify `parameters.json` or `parameters.dev.json`

### To add/modify deployment hooks:
- Edit or add scripts in `infra/hooks/`
- Update `azure.yaml` hooks section

### To change azd configuration:
- Edit `azure.yaml` for general settings
- Edit `.env.template` to document new environment variables

## Environment Variables (azd)

Defined in `.env.template` and used in `infra/main.parameters.json`:

**Required:**
- `MYSQL_ADMIN_PASSWORD`

**Optional (with defaults):**
- `MYSQL_ADMIN_USER` (default: mysqladmin)
- `WORDPRESS_DB_NAME` (default: wordpress)
- `SITE_NAME` (default: wpsite)
- `WORDPRESS_IMAGE` (default: wordpress:php8.2-fpm)
- `NGINX_IMAGE` (default: nginx:alpine)
- `ALLOWED_IP_ADDRESS` (default: empty)
- `PHP_SESSIONS_IN_REDIS` (default: false — enables Redis-backed PHP sessions and disables sticky sessions)

**Auto-set by azd:**
- `AZURE_ENV_NAME` (your environment name)
- `AZURE_LOCATION` (your selected region)

## File Synchronization

Some files exist in both root and `infra/` directories for backward compatibility:

| Root | infra/ | Synchronized? | Notes |
|------|--------|---------------|-------|
| `main.bicep` | `infra/main.bicep` | No | infra version has additional azd outputs |
| `nginx.conf` | `infra/nginx.conf` | Yes | Keep these identical |

## Getting Started

### For New Users (azd):
1. Read `README.md`
2. Follow `AZD_GUIDE.md`
3. Use `QUICK_REFERENCE.md` for commands

### For Existing Users (Legacy):
1. Read `MIGRATION_GUIDE.md`
2. Decide: migrate to azd or continue with legacy
3. Refer to `README.md` for legacy instructions

### For Developers:
1. Read `ARCHITECTURE.md` for system design
2. Check `PROJECT_STRUCTURE.md` (this file) for file organization
3. Modify `infra/main.bicep` for infrastructure changes

## Maintenance Checklist

When updating the project, ensure:

- [ ] `infra/main.bicep` and `main.bicep` stay compatible
- [ ] `infra/nginx.conf` and `nginx.conf` stay synchronized
- [ ] `AZD_GUIDE.md` reflects any azd configuration changes
- [ ] `README.md` includes both azd and legacy instructions
- [ ] `MIGRATION_GUIDE.md` updated if migration process changes
- [ ] `.env.template` documents all environment variables
- [ ] `QUICK_REFERENCE.md` includes new commands/features

## Related Resources

- Azure Developer CLI: https://learn.microsoft.com/azure/developer/azure-developer-cli/
- Azure Container Apps: https://docs.microsoft.com/azure/container-apps/
- Azure Bicep: https://docs.microsoft.com/azure/azure-resource-manager/bicep/
- WordPress: https://wordpress.org/documentation/
