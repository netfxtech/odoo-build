# odoo-build

Builds the NetFX Odoo 19.0 image (Community + Enterprise) using `build.sh`.

## Quick start

```bash
./build.sh --tag netfxtech/odoo:19.0-arm-beta
```

This builds the `production` target and loads it into the local Docker image
store. It does **not** push. To publish:

```bash
docker push netfxtech/odoo:19.0-arm-beta
```

## How the build gets the Enterprise source

The Dockerfile clones `git.netfxtech.cloud/odoo/enterprise.git` through a
BuildKit secret. `build.sh` gets the GitLab token and passes it to
`docker buildx` through an environment variable, so the token never gets
written to disk or included in the build context.

Where the token comes from (first match wins):

1. **Local override:** `~/.config/bws/gitlab.netrc`, a file containing
   `export GITLAB_NETRC=<glpat-...>`. If it exists, Bitwarden is skipped.
2. **Bitwarden Secrets Manager:** the `GITLAB_NETRC` secret, read with the
   `bws` CLI (installed at `/usr/local/bin/bws`). It needs
   `BWS_ACCESS_TOKEN`, either exported or set in `~/.config/bws/token.env`.
   It also needs `jq`.

## Common options

| Command | Effect |
| --- | --- |
| `./build.sh` | Build `odoo-build:19.0` (default tag) |
| `./build.sh --tag <name:tag>` / `-t` | Custom image tag |
| `./build.sh --target builder` | Stop at the builder stage |
| `./build.sh --ref <branch>` | Enterprise git ref (default `19.0`) |
| `./build.sh --emit-netrc ./nrc` | Write the netrc file instead of building (delete it afterwards) |
| `./build.sh -- --no-cache` | Pass extra flags to `docker buildx build` |

You can also set these with environment variables: `IMAGE_TAG`,
`BUILD_TARGET`, `ENTERPRISE_REF`, `ODOO_VERSION`, `BWS_SECRET_KEY`,
`BWS_SECRET_ID`, `TOKEN_ENV_FILE`, `GITLAB_NETRC_FILE`.

Run `./build.sh --help` for the built-in usage text.

## Notes

- This node is ARM64 (aarch64). Python packages must have aarch64 wheels for
  Python 3.12. For example, `cadquery` is pinned to `2.8.0` because older
  releases need `cadquery-ocp<7.9`, which has no aarch64 wheel.
