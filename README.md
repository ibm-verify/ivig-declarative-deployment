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
- 11.0.0.0
- 11.0.0.0_IF1
- 11.0.0.0_IF2
- 11.0.0.1
- 11.0.0.1_IF (with chart 2.1.1)

There is no intention to backport newer chart version to support older IVIG versions.


Strictly speaking, the only third party dependency is helm, version 3.18 or newer. Therefore continuous delivery platform which supports helm should be supported but explicit testing was done on ArgoCD only.

### System Requirements

There is not specific system requirements other than those of IVIG, which will be deployed via this project.

## Versions

### 2.1.0

This version uses helm templates to dynamically render property files in the data folder:
- enRole.properties
- enRoleDatabase.properties
- enRoleLDAPConnection.properties
- enRoleMail.properties

These templates are stored in `data-tpl` folder. Other files can be placed into the data folder and will be used to generate configmaps the same way as before, these are not treated as templates.

Platform credentials are not stored to any template under data-tpl. (And should not be stored under version control at all...) The respective properties are left empty. Sensitive data is injected dynamically before `initIMContainer.sh` runs and stored to the property files within the container in an encrypted form. Credential injection applies to the following:
- enrole.appServer.systemUser.credentials in enRole.properties
- enrole.appServer.ejbuser.credentials in enRole.properties
- database.db.adminPwd in enRoleDatabase.properties
- database.db.password in enRoleDatabase.properties
- java.naming.security.credentials in enRoleLDAPConnection.properties
- mail.smtp.auth.password in enRoleMail.properties

License keys are preferably also not hardcoded in files, but at the same time it is expected that IVIG can be deployed automatically. License keys and other project-specific configuration can be passed via `values-config.yaml` in a format which is a subset of the format used by `config.yaml`.

The file `config.yaml` a needs to exist in it's reduced form (post-installation form) for declarative deployment and preferred to not contain any sensitive data in the form it is stored in Git. Therefore, activation key is dynamically substituted by the templating engine. Any configuration option currently not covered by `values-config.yaml` can be manually added to `config.yaml`.

### 2.0.2

This version attempt to be as close to the original StartetKit as possible, but provide the ability to deploy from Git, with helm only.
- uses the Starterkit as a starting point, maintaining as much compatiblity as possible (a subset of the original folder structure is used)
- all modifications are contained a folder named `argo`
- include the `config` and `data` folder as-is, via symlinks
- reuse as many existing template as possible, via symlinks under `argo/templates`
- eliminates tarballs hardcoded in helm templates e.g. configmaps isvgimks and isvgimdata
- eliminate the usage of any script which generates helm tempates 'on the fly' such as `createConfigs.sh`
- eliminate the `yaml` folder completely
- the `bin` folder is retained in it's original version but is never used

## Setup guide - standalone

### Prerequisites
- k8s cluster up and running
- namespace and registry pull secret configured
- data tier ready and available

### Repo setup

- Check out this project, adjust `values.yaml` and `values-config.yaml` for your environment
- Generate keystore and certs offline (or in another environment) and store these to git
- Provide sensitive data in file `secrets.yaml`, use `secrets.yaml.envsubst` as template

### Deploy

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

This section may contains near and mid term plans, uncommitted feature candidates and general information about the future of the project.

### Features under consideration

- config property `general.install.external-credentials` to control if credentials will be managed via helm chart or externally
- eliminate the requriements to store `isvgimks` by initializeing one on-the-fly on container init
- move pre-init logic to a separate init container

## Further Documentation

This section points the reader to further documentation within the repository (resources in the `docs` folder) or outside of the repository.

- [Introductory Presentations](https://ibm.ent.box.com/folder/335821059835?s=gpwqalbj81ku5tc67rqdc6r2etqse862)
- [Guidelines for Contributors](docs/CONTRIBUTING.md)
- [Changelog for Developers](CHANGES.md) 
- Marketing flyers, Offering and Asset Information
- Demos: see the `demo` branch here in git.

## Contacts

Tibor Bősze <tibor.boesze@nospam.ibm.com>

*This project is supported on a best effort basis by the contributors in spare
time. Issues should be reported via GitHub. Maintenance and development of
enhancements may be provided on a commercial basis, depending on the
availability of the project team.*

