# XtraDeb package CI tooling

This repository contains GitHub-based tooling used to maintain the [XtraDeb](https://xtradeb.net/) package repository for Ubuntu Linux.

## Workflows

### XtraDeb package CI (package.yml)

| Input (parameter name) | Description |
| ---------------------- | ----------- |
| `source` | URL to a Debian source package `.dsc` file, or `.git` repository. Note that only a small set of URLs are accepted. |
| `max-time` | Maximum amount of time, in minutes, to spend in the test build. If the test build is still running when time runs out, it will be considered to have passed successfully. |
| `ppa` | Which XtraDeb PPA (**apps**, **play**, **deps**, **test**) to upload to, or **no-upload** for none. |
| `source-hash` | Optional SHA-256 hash of the `.dsc` file, specified as `sha256:abcd...7890`. If the source-package signature cannot be verified, then this hash will be required to proceed. |
| `subset-release` | A space-separated list of codenames (e.g. `jammy noble`) for which the package should be built. If unspecified, then try to build for all active releases that lack an official package with the same or newer upstream version. Alternately, specifying `NO_VERSION_CHECK` builds for releases regardless of what versions are already available. Note: The set of releases targeted may be further reduced by the package conversion script. |
| `xd-convert-rev` | Git revision of [xtradeb-convert](https://bitbucket.org/xtradeb/xtradeb-convert) to use for the conversion. (Some special values are allowed here.) |
| `xd-version-major` | XtraDeb version major to use for the converted package(s). E.g. if 9 is specified, then the final package version might be `1.2.3-1xtradeb9.2404.1`. Default value is 1. |
| `xd-version-minor` | XtraDeb version minor to use for the converted package(s). E.g. if 9 is specified, then the final package version might be `1.2.3-1xtradeb1.2404.9`. Default value is 1. |
| `include-source` | Whether or not to include the orig source tarball(s) in the upload. The default is to determine this automatically, which should work in most cases. |
| `run-name` | Title to use for the workflow run, instead of "XtraDeb package CI". |

### Launchpad action (lp-action.yml)

| Input (parameter name) | Description |
| ---------------------- | ----------- |
| `action` | Either **retry** (restart any builds that have failed in a transient manner), or **copy** (copy a package, including binaries, from one release to another). |
| `ppa` | Which XtraDeb PPA (**apps**, **play**, **deps**, **test**) to operate on. |
| `package` | Name of source package to operate on. |
| `orig-release` | (**copy** only) Release from which the package should be copied, specified as a codename (e.g. `jammy`). If the name is prefixed with `primary-`, e.g. `primary-jammy`, then the package will be copied from the primary Ubuntu archive. |
| `dest-release` | (**copy** only) Release to which the package should be copied, specified as a codename (e.g. `noble`). |
