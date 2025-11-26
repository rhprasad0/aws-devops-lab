# Dev Container Security Model

This document describes the security architecture of the development container used for AI coding agent sandboxing in the AWS DevOps Lab.

## Threat Model

The primary threat is **prompt injection attacks** where malicious content in code, files, or repositories manipulates the AI agent into executing harmful actions:

| Threat | Example Attack | Mitigation |
|--------|---------------|------------|
| Ransomware | Agent encrypts host files | Container isolation - no host access |
| Credential theft | Agent exfiltrates `~/.aws/credentials` | SSO tokens only, isolated in container |
| Container escape | Agent uses Docker socket to escape | No Docker socket mounted |
| Privilege escalation | Agent uses `sudo` to become root | Non-root user, no sudo |
| Kernel exploit | Agent uses `ptrace` or `mount` | Seccomp profile blocks syscalls |
| Data exfiltration | Agent sends data to attacker server | Network allowlisting (optional) |

## Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Host System (Protected)                                     │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  Docker Container (Isolated)                            ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │  Non-root user (vscode)                             │││
│  │  │  ┌───────────────────────────────────────────────┐  │││
│  │  │  │  Workspace (/workspaces/aws-devops-lab)       │  │││
│  │  │  │  - Read-write: workspace only                 │  │││
│  │  │  │  - No host filesystem access                  │  │││
│  │  │  └───────────────────────────────────────────────┘  │││
│  │  │  Security layers:                                   │││
│  │  │  - seccomp: restricted syscalls                     │││
│  │  │  - No Docker socket                                 │││
│  │  │  - Dropped capabilities                             │││
│  │  │  - AWS SSO: short-lived tokens only                 │││
│  │  └─────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Security Controls

### 1. Container Isolation

The dev container runs in Docker with strict isolation:

- **No host filesystem access**: Only the workspace directory is mounted
- **No Docker socket**: Prevents container escape attacks
- **Bridge networking**: No direct host network access

### 2. Non-Root User

The container runs as user `vscode` (UID 1000), not root:

- Cannot modify system files
- Cannot install system packages
- Limited impact if compromised

### 3. Seccomp Profile

A custom seccomp profile (`.devcontainer/seccomp-profile.json`) blocks dangerous syscalls:

| Blocked Syscall | Why |
|-----------------|-----|
| `ptrace` | Prevents debugging/tracing other processes |
| `mount`/`umount` | Prevents filesystem manipulation |
| `reboot` | Prevents system reboot |
| `init_module` | Prevents kernel module loading |
| `kexec_load` | Prevents loading new kernel |
| `bpf` | Prevents BPF program loading |
| `userfaultfd` | Prevents exploitation vectors |

### 4. Dropped Capabilities

All Linux capabilities are dropped except:

- `NET_BIND_SERVICE`: Allow binding to low ports (optional)

This prevents privilege escalation even if vulnerabilities exist.

### 5. AWS SSO Credentials

**DO NOT** mount your host's `~/.aws` directory into the container.

Instead, use AWS SSO with short-lived tokens:

```bash
# Inside the container
aws configure sso
# Follow prompts to set up SSO

# Each session, login fresh
aws sso login --profile your-profile
```

Benefits:
- Tokens auto-expire (max 12 hours)
- No long-lived credentials to steal
- Credentials isolated inside container

## AWS SSO Setup

### First-Time Setup

1. Open the dev container in Cursor
2. Configure SSO:

```bash
aws configure sso
# SSO session name: dev-lab
# SSO start URL: https://your-org.awsapps.com/start
# SSO region: us-east-1
# SSO registration scopes: sso:account:access
```

3. Select your account and role when prompted
4. Set a profile name (e.g., `dev-lab`)

### Daily Login

Each time you start the container:

```bash
aws sso login --profile dev-lab
```

This opens a browser for authentication and stores a temporary token.

### Verify Credentials

```bash
aws sts get-caller-identity --profile dev-lab
```

## Verification Commands

After starting the container, verify security controls:

```bash
# Should fail - no root access
sudo whoami
# Expected: "vscode is not in the sudoers file"

# Should fail - no Docker socket
docker ps
# Expected: "Cannot connect to the Docker daemon"

# Should fail - can't write outside workspace
touch /etc/test
# Expected: "Permission denied"

# Should fail - ptrace blocked by seccomp
strace ls
# Expected: "Operation not permitted"

# Show limited capabilities
cat /proc/self/status | grep Cap
# CapEff should show minimal capabilities
```

## Optional: Network Allowlisting

For maximum security, you can restrict outbound network access to specific endpoints.

### Using iptables (Advanced)

Create a script to allowlist only required endpoints:

```bash
#!/bin/bash
# network-restrict.sh - Run as root on the host

# Allow established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow specific hosts
ALLOWED_HOSTS=(
    "github.com"
    "api.github.com"
    "*.amazonaws.com"
    "registry.terraform.io"
    "releases.hashicorp.com"
)

for host in "${ALLOWED_HOSTS[@]}"; do
    # Resolve and allow
    iptables -A OUTPUT -d $(dig +short $host) -j ACCEPT
done

# Block everything else
iptables -A OUTPUT -j DROP
```

**Note**: Network restriction is optional and may break some tools. Start without it and add if needed.

## What This Does NOT Protect Against

1. **Actions within allowed scope**: Agent can still delete workspace files
2. **Exfiltration via allowed endpoints**: Agent could push secrets to GitHub
3. **Malicious committed code**: Still need human code review
4. **Social engineering**: Agent could trick you into running dangerous commands

### Mitigations for Remaining Risks

- **Use Cursor's approval dialogs**: Review agent actions before execution
- **Enable GitHub branch protection**: Require PR reviews for changes
- **Regular credential rotation**: Rotate AWS access keys periodically
- **Monitor AWS CloudTrail**: Watch for unusual API activity

## Troubleshooting

### "Permission denied" errors

The container runs as non-root. If a tool needs elevated permissions:

1. First, question if it really needs root
2. Add the tool to the Dockerfile and rebuild
3. Consider if the security risk is acceptable

### AWS commands fail

1. Verify SSO login: `aws sso login --profile dev-lab`
2. Check token expiry: SSO tokens expire after 12 hours
3. Verify profile: `aws configure list --profile dev-lab`

### seccomp blocking legitimate operations

If a tool fails due to seccomp:

1. Check the error message for the blocked syscall
2. Evaluate if the syscall is truly needed
3. If safe, add it to the allowlist in `seccomp-profile.json`

## File Reference

| File | Purpose |
|------|---------|
| `.devcontainer/devcontainer.json` | Main configuration |
| `.devcontainer/Dockerfile` | Container image definition |
| `.devcontainer/seccomp-profile.json` | Syscall restrictions |
| `DEVCONTAINER_SECURITY.md` | This document |

## References

- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Seccomp Security Profiles](https://docs.docker.com/engine/security/seccomp/)
- [AWS SSO CLI Configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)

