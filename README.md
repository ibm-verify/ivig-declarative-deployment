# IVIG Declarative Deployment

Alternative deployment method for IBM Verify Identity Governance for GitOps-driven K8s environments

## Goals and Scope

The goal of the project is to provide an alternative deployment concept which allows deploying IVIG from scratch via GitOps-driven continuous delivery - which is standard in cloud native environments.

The desired state is stored in Git and based on this, declarative deployment (diff/sync) happens via K8s native tools as an alternative to the current StarterKit Linux scripts. The approach itself is tool agnostic, the "reference implementation" was tested with Argo CD which has become a standard for GitOps-driven continuous delivery for K8s and was chosen for the particular client project.

### High level goals
- Minimal amount of human actions (low effort and low risk of human errors)
- Ability to keep stages (e.g. DEV, TEST, PROD) configured similarly (avoid "configuration drift" to reduce operational risk, increase test reliability, easily separate stage agnostic and stage specific configuration)
- Ability to know what is currently deployed where, audit-ability via clear history of changes
- Ability to verify if deployment is "correct" (deployed state equals desired state) to ensure there is no error or deviation
- Ability to be able to rollback to former state
- Ability to deterministically finish a deployment easily, producing the same final result even with transient errors in between (resilient deployment, idempotency, “self healing”)

### Lower level objectives
- Move as much as possible to pure declarative deployment
- Clean separation of sensitive and non-sensitive configuration data
- Deployment from Git with environment specific variables
- Deployment using externally managed secrets (Vault)
- No extra dependencies (vs Starterkit) but integrate with cloud native CD tools e.g. Argo CD (whereas Starterkit does not).
- Observability/visibility increased due to "normalized" repo structure
- Detect and remediate configuration shift, rollback, central desired state in Git
- Avoid chicken-egg problem, enable creation of desired state before containers are deployed to cluster (crucial for air-gapped environment)
- Ability to deploy any Fixpack or Interim Fix version right away, without installing 11.0.0.0 and then sequentially updating to each Fixpack or Interim Fix

### Out of Scope
- ~deployment of data tier (expected to be present as prerequisite)~(chart 2.2.1 enables optional deployment of DB and LDAP intended for non-production use)
- configuration of External User Registry
- configuration of the analytics module
- ~issuing x509 certificates (expected to be present as prerequisite)~(version 2.2.2 ships setup scripts which automate certificate generation)

## Components and Dependencies

This project delivers a Helm chart that deploys IBM Verify Identity Governance. The chart versions required to install a specific IVIG versions are listed below:
- 11.0.0.0 (as of chart 2.0.0)
- 11.0.0.0_IF1
- 11.0.0.0_IF2
- 11.0.0.1 (as of chart 2.0.2)
- 11.0.0.1_IF1 (as of chart 2.1.1)
- 11.0.1.0 (as of chart 2.1.4)
- 11.0.1.1 (as of chart 2.2.4)
- 11.0.1.1_IF1 (as of chart 2.3.1)
- 11.0.2.0 (as of chart 2.4.0)

There is no intention to backport newer chart versions to support older IVIG versions. A version history including all notable changes is maintained in the [Changelog](CHANGES.md). This document covers the most recent version of the Helm chart. Older versions of documentation for older chart version can be retrieved from Git history.

### The Big Picture

The declarative deployment method for IVIG follows a relaxed layered architecture where some layers are optional:

0. GitOps is a concept that applies version control and CI/CD to infrastructure automation, ensuring consistent and repeatable deployment.
1. At the core, a Helm chart implements the deployment logic. It can be deployed without using any third party component other than Helm - this approach is referred to as a [pure Helm standalone setup](docs/PURE-HELM.md) and described in detail. It is imperative to read this documentation as it serves as a foundation for subsequent layers as well.
2. Argo CD is a higher-level GitOps-driven continuous delivery platform for K8s which supports Helm and Git and handles cluster synchronisation. This optional deployment approach builds on the previous layer. Read the [recommended approach for a multi-stage project via Argo CD](docs/ARGO-CD.md) after processing the documentation of the previous layer.
3. External Secrets Operator is a K8s operator that syncs sensitive data from external secret management systems (such as HashiCorp Vault) into K8s Secrets. [Integration with Vault via External Secrets](docs/VAULT.md) is optional and can be used with [pure Helm](docs/PURE-HELM.md) as well as [Argo CD](docs/ARGO-CD.md).

### System Requirements

Strictly speaking, the only third party dependency is Helm, version 3.18 or newer. Therefore any continuous delivery platform which supports Helm should be supported but explicit testing was done on Argo CD only.

There are no specific system requirements other than [those of the IVIG version, which will be deployed](https://www.ibm.com/software/reports/compatibility/clarity/index.html?name=IBM%20Verify%20Identity%20Governance). The product documentation boldly states that all versions of Kubernetes are supported, but it is encouraged to use a Kubernetes release which has not reached end-of-life yet.

Optional [Integration with Vault via External Secrets](docs/VAULT.md) has additional dependencies [documented separately](docs/VAULT.md#prerequisites).

### Optional user convenience scripts

There are optional user convenience scripts which can be used for quickly setting up a demo or development environment. These scripts have been specifically developed with efficiency and minimal dependencies in mind and are known to work with the following versions of standard Linux/Unix utilities:
- `cert-setup.sh`: bash 3.2, sed (GNU 4.2, BSD)
- `cert-util.sh`: bash 3.2, OpenSSL 3
- `secrets-setup.sh`: bash 3.2, grep (GNU 3.6, BSD 2.6), OpenSSL 3

Optional Vault integration includes two further non-essential user convenience scripts with the following dependencies:
- `vault-json-pack.sh`: bash 3.2, jq 1.5
- `vault-json-unpack.sh`: bash 3.2, jq 1.5

Note: Although GNU/Linux is the primary target platform, there are users of this project who run macOS. The current version of macOS still ships with an extremely outdated bash version (3.2.57 from 2007) due to GPLv3 licensing issues. Convenience scripts of version 2.3.4 are compatible with this old bash version as well as BSD sed and grep.

## Setup guide - pure Helm

The standalone setup is a viable option for both Developers/Integrators and for teams who have not adopted a full CI/CD solution for GitOps-driven Kubernetes. This setup requires Git, the user will directly interact with `helm` (rather than indirectly via Argo CD) and `kubectl`. The fastest way to get up and running is this minimal standalone setup.

### TL;DR

This section is intended for users intimately familiar with IVIG, Kubernetes and Helm. It provides quick-start instructions in a compact and minimalistic fashion. It is strongly recommended to read and understand the [complete setup guide](docs/PURE-HELM.md) which covers technical details and deployment options.

The code listing below covers a minimal setup from scratch, assuming the user already established `kubectl` connectivity to a K8s cluster which has a storage class called 'local-path'.

**Note:** Due to legal restrictions, no license keys are distributed in this repo. The user has to accept the license and provide activation/license keys for the IBM products to be deployed.

```
git clone https://github.com/ibm-verify/ivig-declarative-deployment.git
cd ivig-declarative-deployment/smarterkit
vi values-config.yaml # fill in general.license section: accept and provide keys
./cert-setup.sh && ./secrets-setup.sh
helm template --dry-run=client -f values.yaml -f values-config.yaml -f secrets.yaml -f regcred.yaml . | kubectl apply -f -
kubectl -n ivig-idm wait --for=condition=Ready --timeout=5m pod -l app=isvgim
kubectl -n ivig-idm exec isvgim-0 -- /bin/bash -c "/work/util/extract-config-response.sh --install && /work/ldapConfig.sh install && /work/dbConfig.sh install"
kubectl -n ivig-idm rollout restart sts/isvgim
```
The following command will wait for the application to start and then print out the login URL. Note that this is a long chained command spread across multiple lines via line continuation (backslash immediately followed by newline).
```
kubectl -n ivig-idm wait --for=condition=Ready --timeout=5m pod -l app=isvgim && \
kubectl -n ivig-idm get pod/isvgim-0 -o jsonpath='Login at https://{.status.hostIP}:' && \
kubectl -n ivig-idm get svc/isvgim -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}{"/itim/console\n"}'
```

This minimal setup could deploy an ephemeral demo environment within minutes, but note that essential data is only stored locally, not committed to a Git repository. The recommended pure Helm approach requires setting up a Git repository to persistently store configuration and provide version control for the deployment.

### Walkthrough of steps and alternative options

This section provides a concise but high level overview of the setup process listing alternative deployment options. It is intended as a quick reference for users who have already read the [complete setup guide](docs/PURE-HELM.md).

1. **Fork & Clone the Repository**
   - Fork this repository to a new Git repo (on GitHub, GitLab, or any other Git hosting platform or self-hosted instance)
   - Clone locally, configure upstream remote, create a project-specific branch (e.g. `demo-xyz`)

2. **Configure Values Files**
   - Adjust `values.yaml`: configure `namespace`, `timezone`, `storage.className`, `storage.mode` etc. for the target environment
   - *Option A:* Edit `values-config.yaml` manually: fill in `general.license` section, choose components to deploy (`deployLdap`, `deployDb`, `deployIsvdi`), configure credentials strategy
   - *Option B:* Convert `config.yaml` created with StarterKit `configure.sh` to `values-config.yaml`
   - *Alternative:* For multi-env projects, adopt a [configuration strategy](docs/ARGO-CD.md#recommended-configuration-strategy), where multiple sources of configuration are merged in a top-down order
   - *Option A:* Decide to store license keys in Git (suitable for private or corporate Git repos with restricted read access)
   - *Option B:* Move [license data to a separate file](docs/PURE-HELM.md#do-not-store-license-keys-in-public-repositories) which will not be stored in Git (required for public Git repos)
   - Commit `values*.yaml` files to Git

3. **Generate x509 Certificates**
   - *Option A:* Run `./cert-setup.sh` for one-click auto-detected certificate creation
   - *Option B:* Use `./cert-util.sh --create` for fine-grained control over SANs and included components (or multiple envs and cert dirs)
   - *Option A:* Commit certs to Git (dev/demo) or
   - *Option B:* Store certs and related files in Vault (production)

4. **Provision Secrets** (do not commit to Git)
   - Run `./secrets-setup.sh` to auto-generate `secrets.yaml` with random passwords and a random data encryption key
   - Configure `regcred.yaml` with image pull secret credentials for the container registry
   - *Option A:* Secure these files locally, to be passed to `helm` as input files in the next step
   - *Option B:* Use External Secrets Operator with HashiCorp Vault or another provider (described later)
   - *Option C:* Pre-provision secrets manually in K8s and set `general.install.externalSecret.*` flags

5. **Deploy to Kubernetes**
   - Dry-run to verify: `helm template --dry-run=client -f values.yaml -f values-config.yaml -f secrets.yaml -f regcred.yaml .` (Note: `regcred.yaml` and `secrets.yaml` can be omitted depending of the option chosen in the previous step)
   - Diff against live state by piping the output to `kubectl diff -f -`
   - Apply desired state by piping the output to `kubectl apply -f -`
   - Pass `--set revision=$(git log -n 1 --pretty=format:%h)` to tag the deployment with the Git commit

6. **Initialize the Data Tier**
   - Wait for the `isvgim` pod[s] to become ready
   - Execute inside the pod: `/work/util/extract-config-response.sh --install && /work/ldapConfig.sh install && /work/dbConfig.sh install`
   - Restart the StatefulSet: `kubectl rollout restart sts/isvgim`

7. **Enable Inbound Connections**
   - *Option A:* Use the [NodePort enabled by default](docs/PURE-HELM.md#via-nodeport-by-default)
   - *Option B:* Configure and [Ingress](docs/PURE-HELM.md#via-ingress)
   - In both cases, ensure firewalls are configured to allow inbound traffic

8. **Verify the Installation**
   - Wait for the application to reach ready state
   - Log in to the IVIG console and list users as a smoke test
   - On errors, check the section on [troubleshooting](docs/PURE-HELM.md#troubleshooting)

## Setup guide - Argo CD

The repository setup and configuration steps described in the standalone setup guide apply to this scenario as well.

On high level, the following sequence of steps should be followed to quickly bootstrap your deployment via Argo CD:
- Check out this project, adjust `values.yaml` and `values-config.yaml` for your environment and check into your Git
- Generate x509 certificates offline (or in another environment) and store these to Git (or optionally, store these in Vault)
- Adjust the application manifest sample in the root directory of this project (optionally use external secrets from Vault)
- Enable automatic sync or sync manually via Argo CD

In a real-life setup, the typical pattern is to deploy multiple environments (such as development, test and production) from a single Git repository. A separate guide describes the [recommended approach for a multi-stage project via Argo CD](docs/ARGO-CD.md).

## External Secrets and Vault Integration

With Vault Integration enabled, you can securely store all or a subset of the [credentials from `secrets.yaml`](docs/PURE-HELM.md#deploy) in Vault, which will be automatically propagated to the K8s cluster and exposed to the containers in a secure manner. Additionally, PKI related files, such as private keys and certificates can also be sourced from Vault and mounted to the containers in a similar way.

Interoperability with Vault is achieved via the use of External Secrets. The External Secrets Operator interacts with [HashiCorp Vault](https://www.vaultproject.io/), [IBM Cloud Secrets Manager](https://www.ibm.com/cloud/secrets-manager) or external secret management systems like [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/), [Google Secrets Manager](https://cloud.google.com/secret-manager), [Azure Key Vault](https://azure.microsoft.com/en-us/services/key-vault/), [CyberArk Conjur](https://www.conjur.org/).

Integration with Vault or another secret management system is documented in detail [here](docs/VAULT.md).

## Hardening and extra features

This project delivers many [extras not included in the original product](docs/EXTRAS.md) which are mostly geared towards enhancing security:
- Redesigned, more secure approach to working with sensitive data
  - Proper separation of sensitive and non-sensitive data
  - Dynamic credential injection
  - Improved protection of data encryption keys
  - Interoperability with external secret management systems such as HashiCorp Vault
- Custom flags for selectively enabling general hardening measures
- Measures to avoid deadlocks on restart
- Fixes of bugs which impact security but have not been addressed in the original product yet

## Future plans

This section contains near and mid term plans, uncommitted feature candidates and general information about the future of the project.

### General information

There is general intention to maintain compatibility with upcoming versions of the product. After the release of new product versions (including Fixpacks and Interim Fixes), it will be analysed if any change would break functionality of the declarative deployment method implemented in this project. The required strategic changes should be implemented in a reasonably short timeframe in order to support the new product version. Each release of this project clearly mentions the target product version it can deploy.

Based on severity, effort required and available capacity, some defects or weaknesses introduced in a future version of the product may be compensated in this project until an upstream fix is available. The dynamic patching capability allows applying small patches efficiently, and will be used in exceptional cases when waiting several weeks for an official product fix would have severe negative impact.

### Features under consideration

- ~config property `general.install.externalSecret` to control if credentials will be managed via Helm chart or externally~ DONE
- ~move pre-init logic to a separate init container~ DONE
- ~eliminate the need to store `isvgimks` by initializing one on-the-fly during initialization~ DONE
- ~optional/modular deployment of postgres DB and LDAP into the same namespace for demo or development~ DONE
- ~convenience utility for DB and LDAP upgrade and initial schema and data load~ DONE
- ~credentials from external secrets (optional, selectively configurable)~ DONE
- ~x509 certificates and key from external secrets (optional, selectively configurable)~ DONE
- ~HashiCorp Vault integration walkthrough~ DONE

## Further Documentation

This section points the reader to further documentation within the repository (resources in the `docs` folder) or outside the repository.

- [Complete Guide - pure Helm](docs/PURE-HELM.md)
- [Recommended approach for a multi-stage project via Argo CD](docs/ARGO-CD.md)
- [External Secrets and Vault Integration Guide](docs/VAULT.md)
- [Guidelines for Contributors](CONTRIBUTING.md)
- [Changelog](CHANGES.md)

## Contacts

Design and implementation:

| Name        | GitHub ID                        | Affiliation                |
| ----------- | -------------------------------- | -------------------------- |
| Tibor Bősze | [@tb00](https://github.com/tb00) | IBM Technology Expert Labs |

