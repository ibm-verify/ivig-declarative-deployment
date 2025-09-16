# IVIG Declarative Deployment

Alternative deployment method for IBM Verifiy Identity Governance for GitOps-driven K8s environments

## Goals and Scope

The goal of the project is to provide an alternative deployment concept which allows deploying IVIG from scratch via GitOps-driven continuous delivery - which is standard in cloud native environments.

The desired state is stored in git and based on this, declarative deployment (diff/sync) happens via K8s native tools as an alternative to the current StarterKit Linux scripts. The approach itself is tool agnostic, the "reference implementation" was tested with Argo CD which has become a standard for GitOps-driven continuous delivery for K8s and was chosen for the particular client project.

### High level goals
- Minimal amount of human actions (low effort and low risk of human errors)
- Ability to keep stages (e.g. DEV, TEST, PROD) configured similarly (avoid "configuration drift" to reduce operational risk, increase test reliability, easily separate stage agnostic and stage specific configuration)
- Ability to know what is currently deployed where, audit-ability via clear history of changes
- Ability to verify if deployment is "correct" (deployed state equals desired state) to ensure there is no error or devation
- Ability to be able to rollback to former state
- Ability to deterministically finish a deployment easily, producing the same final result even with transient errors inbetween (resilient deployment, idempotency, “self healing”)

### Lower level objectives
- Move as much as possible to pure declarative deployment
- Clean separation of sensitive and non-sensitive configuration data
- Deployment from git with environment specific variables
- Deployment using externally managed secrets (vault)
- No extra dependencies (vs Starterkit) but integrate with cloud native CD tools e.g. ArgoCD (whereas Starterkit does not).
- Observability/visibility increased due to "normalized" repo structure
- Detect and remediate configuration shift, rollback, central desired state in git
- Avoid chicken-egg problem, enable creation of desired state before containers are deployed to cluster (crucial for air-gapped environment)
- Ability to deploy any Fixpack or Interim Fix version right away, without installing 11.0.0.0 and then sequentially updating to each FixPack or Interim Fix

### Out of Scope
- deployment of data tier (expected to be present as prerequisite)
- configuration of External User Registry
- configuration of the analytics module
- creating keystore and issuing certificates (expected to be present as prerequisite)

## Components and Dependencies

This project targets following IBM Verifiy Identity Governance versions:
- 11.0.0.0 (as of chart 2.0.0)
- 11.0.0.0_IF1
- 11.0.0.0_IF2
- 11.0.0.1 (as of chart 2.0.2)
- 11.0.0.1_IF (as of chart 2.1.1)

There is no intention to backport newer chart version to support older IVIG versions.

Strictly speaking, the only third party dependency is helm, version 3.18 or newer. Therefore continuous delivery platform which supports helm should be supported but explicit testing was done on ArgoCD only.

### System Requirements

There is not specific system requirements other than those of IVIG, which will be deployed via this project.

## Versions

A version history including all notable changes is maintained in the [Changelog](CHANGES.md). Keep in mind that there is no intention to backport newer chart version to support older IVIG versions.

## Setup guide - standalone

The standalone setup is a viable option for both Developers/Integrators and for team who have not adopted a full CI/CD solution for GitOps-driven Kubernetes. This setup requires Git, the user will directly interact with `helm` (rather than indirectly via ArgoCD). The fastest way to get up and running is this minimal standalone setup.

### Prerequisites
- k8s cluster up and running
- namespace and registry pull secret configured
- data tier ready and available

### Repo setup

As a first step, check out this project from git or even better, fork it to create your own project specific repo.

Next, adjust `values.yaml` and `values-config.yaml` for your environment and store them your git project. Users unfamiliar with the procut may run `bin/configure.sh -manual` to generate `config.yaml` which may then be used as a baseline for `values-config.yaml`, as these file follow the same structure with minimal deviations. Keep the following in mind:

-  Adjust `values.yaml`:
  -  `namespace`, `timezone`, `licenseType`, `storage.className` and `storage.mode` are only read from `starterkit/argo/values.yaml`, define them there!
  -  `clusterUrl` is not used, leave it as-is.
-  If you decide to use `bin/configure.sh -manual` to generate `config.yaml` then just copy the the content to `values-config.yaml` and adjust as follows:
  - `general.install`: it is advices to only retain properties which are defined in `values-config.yaml`, others are not used
  - `general.install.externalSecret`: while it is not supported by the original starterkit and therefore absent in `config.yaml`, use this to selectively configure Vault integration for MQ, OIDC or platform credentials
  - `externalRegistry`: it is not supported - it will not cause any error but it is recommended to remove this section to avoid confusion
  - `server.truststore`: as `bin/configure.sh -manual` may leave it empty or incomplete, make sure there is at least the list item `  - '@isvgimRootCA.crt'` present
  - `oidc`: while this section is not generated by the original starterkit and therefore absent in the generated `config.yaml`, we support it and the same intruction apply for OIDC setup (if you already configured OIDC in one of your deployments, just append the `oidc` section to `values-config.yaml`

The next step is to generate keystore and certs offline (or in another environment) and store these to git.
(TODO: step-by-step guide)

### Deploy

As the last step before deployment, sensitive data which should not be put under version control needs to be dealt with.

There are two alternative approaches to handling credentials:
- Provide sensitive data in file `secrets.yaml`, use `secrets.yaml.envsubst` as template
- Use external secrets for Vault integration

#### Vault integration via External Secrets (optional) 

Interoperability with Vault is achieved via the use of External Secrets. The External Secrets Operator interacts with [HashiCorp Vault](https://www.vaultproject.io/), [IBM Cloud Secrets Manager](https://www.ibm.com/cloud/secrets-manager) or external secret management systems like [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/), [Google Secrets Manager](https://cloud.google.com/secret-manager), [Azure Key Vault](https://azure.microsoft.com/en-us/services/key-vault/), [CyberArk Conjur](https://www.conjur.org/).

The optional Vault integration can be configured via `general.install.externalSecret` selectively for MQ, OIDC and platform credentials, and is disabled by default.

#### Common tasks

When working directly with `helm` rather than via ArgoCD (which is a viable option for both Developers/Integrators and for team who have not adopted a full CI/CD solution for GitOps-driven Kubernetes) see the following list of commands which illustrate various DevOps tasks.

```
## Development/integration

# inspect the output of a single template (from within the argo directory)
helm template --dry-run -f values.yaml -f values-config.yaml -f secrets.yaml -s templates/201-deployment-isvgimconfig.yaml .
# split output into separate files for each template and store to output-dir for inspection/debugging
helm template --dry-run -f values.yaml -f values-config.yaml -f secrets.yaml . | ../../helm-fan-out.sh output-dir

## Normal operation

# compare desired state with currently deployed state
helm template --dry-run -f values.yaml -f values-config.yaml -f secrets.yaml . | kubectl diff -f -

# enforce desired state
helm template --dry-run -f values.yaml -f values-config.yaml -f secrets.yaml . | kubectl apply -f -
```

### Install Verification Test

The first fundamental check is to log on to IVIG and list users.

Execute smoke tests for your IVIG project as necessary. (Smoke tests are a subset of test cases that cover the most important functionality of a component or system, used to aid assessment of whether main functions of the software appear to work correctly.)

### Troubleshooting guide

Review k8s events and IVIG application logs:
```
kubectl events -n <namespace>

kubectl logs -n <namespace> isvgim-0 -c logs-im
```
Check the avalability and configuration of your database and LDAP instance.

## Setup guide - ArgoCD

- Check out this project, adjust `values.yaml` and `values-config.yaml` for your environment and check into your git
- Generate keystore and certs offline (or in another environment) and store these to git
- Adjust the application manifest sample in the root directory of this project (use external or internal vault)
- Enable automatic sync or sync manually via ArgoCD

## Future plans

This section contains near and mid term plans, uncommitted feature candidates and general information about the future of the project.

### Features under consideration

- -config property `general.install.externalSecrets` to control if credentials will be managed via helm chart or externally- DONE
- eliminate the requriements to store `isvgimks` by initializeing one on-the-fly on container init
- move pre-init logic to a separate init container

## Further Documentation

This section points the reader to further documentation within the repository (resources in the `docs` folder) or outside of the repository.

- [Introductory Presentations](https://ibm.ent.box.com/folder/335821059835?s=gpwqalbj81ku5tc67rqdc6r2etqse862)
- [Guidelines for Contributors](docs/CONTRIBUTING.md)
- [Changelog](CHANGES.md) 
- Marketing flyers, Offering and Asset Information
- Demos: see the `demo` branch here in git.

## Contacts

Tibor Bősze <tibor.boesze@nospam.ibm.com>

*This project is supported on a best effort basis by the contributors in spare
time. Issues should be reported via GitHub. Maintenance and development of
enhancements may be provided on a commercial basis, depending on the
availability of the project team.*

