# Remote Cache Setup

Share prebuilt xcframeworks across a team using Git or S3 backends.

## Table of Contents

1. [Git Backend](#git-backend)
2. [S3 Backend](#s3-backend)
3. [Pull/Push Commands](#pullpush-commands)

## Git Backend

1. Create a dedicated Git repo for cache storage.
2. Configure in `spm-cache.yml`:

```yaml
remote:
  debug:
    git: git@github.com:your-org/ios-spm-cache.git
  release:
    git: git@github.com:your-org/ios-spm-cache-release.git
```

## S3 Backend

1. Create an S3 bucket.
2. Create credentials file at `~/.spm-cache/s3.creds.json`:

```json
{
  "access_key_id": "AKIA...",
  "secret_access_key": "..."
}
```

3. Configure in `spm-cache.yml`:

```yaml
remote:
  debug:
    s3:
      uri: "s3://your-org-spm-cache/debug"
      creds: "~/.spm-cache/s3.creds.json"
```

4. Install AWS CLI: `pip install awscli`

## Pull/Push Commands

```bash
spm-cache remote pull --config=debug
spm-cache remote push --config=debug
```
