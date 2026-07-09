# IVIG Declarative Deployment

Alternative deployment method for IBM Verify Identity Governance for GitOps-driven K8s environments

## Goals and Scope

The goal of the project is to provide an alternative deployment concept which allows deploying IVIG from scratch via GitOps-driven continuous delivery - which is standard in cloud native environments.

The desired state is stored in git and based on this, declarative deployment (diff/sync) happens via K8s native tools as an alternative to the current StarterKit Linux scripts. The approach itself is tool agnostic, the "reference implementation" was tested with Argo CD which has become a standard for GitOps-driven continuous delivery for K8s and was chosen for the particular client project.

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
- Deployment from git with environment specific variables
- Deployment using externally managed secrets (vault)
- No extra dependencies (vs Starterkit) but integrate with cloud native CD tools e.g. ArgoCD (whereas Starterkit does not).
- Observability/visibility increased due to "normalized" repo structure
- Detect and remediate configuration shift, rollback, central desired state in git
- Avoid chicken-egg problem, enable creation of desired state before containers are deployed to cluster (crucial for air-gapped environment)
- Ability to deploy any Fixpack or Interim Fix version right away, without installing 11.0.0.0 and then sequentially updating to each FixPack or Interim Fix

### Out of Scope
- ~deployment of data tier (expected to be present as prerequisite)~(chart 2.2.1 enables optional deployment of DB and LDAP intended for non-production use)
- configuration of External User Registry
- configuration of the analytics module
- ~issuing x509 certificates (expected to be present as prerequisite)~(version 2.2.2 ships setup scripts which automate certificate generation)

## Components and Dependencies

This project targets following IBM Verify Identity Governance versions:
- 11.0.0.0 (as of chart 2.0.0)
- 11.0.0.0_IF1
- 11.0.0.0_IF2
- 11.0.0.1 (as of chart 2.0.2)
- 11.0.0.1_IF1 (as of chart 2.1.1)
- 11.0.1.0 (as of chart 2.1.4)
- 11.0.1.1 (as of chart 2.2.4)
- 11.0.1.1_IF1 (as of chart 2.3.1)
- 11.0.2.0 (as of chart 2.4.0)

There is no intention to backport newer chart version to support older IVIG versions.

Strictly speaking, the only third party dependency is helm, version 3.18 or newer. Therefore any continuous delivery platform which supports helm should be supported but explicit testing was done on ArgoCD only.

### System Requirements

There are no specific system requirements other than those of IVIG, which will be deployed via this project.

### Optional user convenience scripts

There are optional user convenience scripts which can be used for quickly setting up a demo or development environment. These scripts have been specifically developed with efficiency and minimal dependencies in mind and are known to work with the following versions of standard Linux/Unix utilities:
- `cert-setup.sh`: bash 3.2, sed (GNU 4.2, BSD)
- `cert-util.sh`: bash 3.2, OpenSSL 3
- `secrets-setup.sh`: bash 3.2, grep (GNU 3.6, BSD 2.6), OpenSSL 3

Note: Although GNU/Linux is the primary target platform, there is at least one user of this project who runs MacOS. The current version of MacOS still ships with an extremely outdated bash version (3.2.57 from 2007) due to GPLv3 licensing issues. Convenience scripts of version 2.3.4 are compatible with this old bash version as well as BSD sed and grep.

## Versions

A version history including all notable changes is maintained in the [Changelog](CHANGES.md). Keep in mind that there is no intention to backport newer chart version to support older IVIG versions.

## Setup guide - standalone

The standalone setup is a viable option for both Developers/Integrators and for teams who have not adopted a full CI/CD solution for GitOps-driven Kubernetes. This setup requires Git, the user will directly interact with `helm` (rather than indirectly via ArgoCD) and `kubectl`. The fastest way to get up and running is this minimal standalone setup.

### TL;DR

#### Quick demo
Minimal setup from scratch, assuming your k8s cluster has a storage class called 'local-path':
```
git clone https://github.com/ibm-verify/ivig-declarative-deployment.git
cd ivig-declarative-deployment/smarterkit && git checkout demo
./cert-setup.sh
./secrets-setup.sh
helm template --dry-run=client -f values.yaml -f values-config.yaml -f secrets.yaml -f regcred.yaml . | kubectl apply -f -
kubectl -n ivig-argo wait --for=condition=Ready --timeout=5m pod -l app=isvgim
kubectl -n ivig-argo exec isvgim-0 -- /bin/bash -c "/work/util/extract-config-response.sh --install && /work/ldapConfig.sh install && /work/dbConfig.sh install"
kubectl -n ivig-argo rollout restart sts/isvgim
```

#### Recommended standalone setup

Setup your own git repo and adjust config as needed:
```
# fork the project on GitHub, then clone it and configure upstream
git clone https://github.com/${YOUR_USER}/ivig-declarative-deployment.git
cd ivig-declarative-deployment/smarterkit
git remote add upstream https://github.com/ibm-verify/ivig-declarative-deployment.git
git checkout demo
# adjust values.yaml and values-config.yaml as needed, generate certs and commit
vi values-config.yaml values.yaml
./cert-setup.sh
git add values-config.yaml values.yaml config/certs/*
git commit -m "init quick demo"
```

Generate secrets (not to be stored in git), then deploy to k8s and initialize data tier:
```
# autogenerate random secrets
./secrets-setup.sh
# deploy desired state
helm template --dry-run=client -f values.yaml -f values-config.yaml -f secrets.yaml -f regcred.yaml --set revision=$(git log -n 1 --pretty=format:%h) . | kubectl apply -f -
# init data tier
kubectl -n $NAMESPACE wait --for=condition=Ready --timeout=5m pod -l app=isvgim
kubectl -n $NAMESPACE exec isvgim-0 -- /bin/bash -c "/work/util/extract-config-response.sh --install && /work/ldapConfig.sh install && /work/dbConfig.sh install"
kubectl -n $NAMESPACE rollout restart sts/isvgim
```

### Prerequisites
- K8s cluster up and running
- ~namespace and registry pull secret configured~ (chart 2.2.5 will deploy the namespace and optionally the pull secret as well)
- data tier ready and available if using an external data tier (chart 2.2.1 enables optional deployment of DB and LDAP intended for non-production use)

### Repo setup

As a first step, check out this project from git or even better, fork it to create your own project specific repo.

```
# fork the project on GitHub, then clone it and configure upstream
git clone https://github.com/${YOUR_USER}/ivig-declarative-deployment.git
cd ivig-declarative-deployment
git remote add upstream https://github.com/ibm-verify/ivig-declarative-deployment.git
```

Next, adjust `values.yaml` and `values-config.yaml` for your environment and store them to your git project. Users unfamiliar with the product may run `bin/configure.sh -manual` to generate `config.yaml` which may then be used as a baseline for `values-config.yaml`, as these file follow the same structure with minimal deviations. Keep the following in mind:

-  Adjust `values.yaml`:
  -  `namespace`, `timezone`, `licenseType`, `storage.className` and `storage.mode` are only read from `smarterkit/values.yaml`, define them there!
  -  `clusterUrl` is not used, leave it as-is.
-  If you decide to use `bin/configure.sh -manual` to generate `config.yaml` then just copy the content to `values-config.yaml` and adjust as follows:
  - `general.install`: it is advised to only retain properties which are defined in the bundled `values-config.yaml`, others are not used
  - `general.install.externalSecret`: while it is not supported by the original StarterKit and therefore absent in `config.yaml`, use this to selectively configure Vault integration for MQ, OIDC or platform credentials
  - `externalRegistry`: it is not supported - it will not cause any error but it is recommended to remove this section to avoid confusion
  - `server.truststore`: as `bin/configure.sh -manual` may leave it empty or incomplete, make sure there is at least the list item `  - '@isvgimRootCA.crt'` present
  - `oidc`: while this section is not generated by the original StarterKit and therefore absent in the generated `config.yaml`, we support it and the same instructions apply for OIDC setup (if you already configured OIDC in one of your deployments, just append the `oidc` section to `values-config.yaml`

The next step is to generate x509 certificates offline (or in another environment). Two openssl-based alternatives are bundled, but of course, one may use any other means to generate certificates.

The `cert-util.sh` script is added to create, renew and list certificates for a configurable set of components. The structure of the certificates is intentionally kept compatible with the original starterkit, but the logic for managing certificates has been externalized, it does not run within the container.

The logic is implemented such that existing cryptographic keys and certificate signing requests are reused when creating or renewing certificates.

Subject alternate names (domain names) are configured according to the requirements of each component, inline with how the original startetkit would create certificates.

This script is intentionally de-coupled and self-contained, it does not have dependencies other than `bash` and `openssl`. 

```
$ cd smarterkit
$ ./cert-util.sh
Create, renew or show certificates used by IVIG deployment
usage: ./cert-util.sh [OPTION...]

Operation modes:
   -c|--create      setup CA, create keys & CSRs if missing, issue certificates
   -r|--renew       issue new certificates for all certificate signing requests
   -l|--list        show quick summary of existing certificates
Options for create:
   -f|--fqdn        comma separated list of DNS subjectAltNames of the app cert
   -n|--namespace   K8s namespace, to be used in isvdi subjectAltName only
   -i|--include     comma separated list of optional components to issue
                    certificates for, defaults to "isvd,isvdi,pgsql"
Additional options:
   -d|--directory   local directory for certificates, defaults to "config/certs"
$ ./cert-util.sh --create
```

As an alternative, another script, `cert-setup.sh` is included to auto-detects the part of configuration that is relevant for certificates, once `values.yaml` and `values-config.yaml` have already been adjusted. In particular, it will retrieve the k8s namespace from `values.yaml`, collect extra hostnames (which should be added to the certificate of IVIG server) and the list of optional components to be deployed from `values-config.yaml`. This script, after collecting the information required, will invoke `cert-util.sh` to create certificates, and after that, to list the details of the certificates created.

```
$ cd smarterkit
$ ./cert-setup.sh
```

Elliptic Curve prime256v1 keys and certificates are created for the following when `cert-setup.sh` is run:
- `isvgimRootCA`
- `isvgim`
- `mq`
- `isvdi` if `general.install.deployIsvdi` is enabled
- `isvd` if `general.install.deployLdap` is enabled
- `pgsql` if `general.install.deployDb` is enabled

While `cert-setup.sh` is intended to be a convenient "one-click" tool to setup a new environment without specifying any input parameter, it is not as robust and versatile as `cert-util.sh` which comes with a rich set of commandline options that allow finer-grained control of the behavior. Of course, due to project-specific requirements one may have to create and manage certificates via alternative means, in which case these two scripts might serve as reference or inspiration.

#### Tips and tricks for certificate creation

One can use `cert-util.sh` to conveniently create additional certificates with arbitrary subject alternate names, signed by `isvgimRootCA`. This is useful when additional certificates need to be created for external data tier components or other components of the target environment, where typically finer grained control over subjectAltNames is also required. The example below demonstrated, how to create a certificate for `foo` and control subject alternative names via the environment variable `FOO_ALTNAME`.

```
$ export FOO_ALTNAME="DNS: foo.com, DNS:*.foo.com"
$ ./cert-util.sh --create --include foo
-----
Certificate request self-signature ok
subject=CN=isvgim, O=isvgim, DC=isvgim
-----
Certificate request self-signature ok
subject=CN=mq, O=isvgim, DC=isvgim
-----
Certificate request self-signature ok
subject=CN=foo, O=isvgim, DC=isvgim
$ ./cert-util.sh --list
Listing subjectAltName and expiration date of certificates:

[foo.crt]
X509v3 Subject Alternative Name: 
    DNS:foo.com, DNS:*.foo.com
notAfter=Mar 10 18:39:28 2031 GMT

[isvgim.crt]
X509v3 Subject Alternative Name: 
    DNS:idm.demo.com, DNS:isvgim
notAfter=Mar 10 18:39:28 2031 GMT

[isvgimRootCA.crt]
No extensions in certificate
notAfter=Mar  8 18:39:28 2036 GMT

[mq.crt]
X509v3 Subject Alternative Name: 
    DNS:mqshare, DNS:mq-headless, DNS:localhost
notAfter=Mar 10 18:39:28 2031 GMT
```

#### Storing certificates and related files

One may store the certificates, CSRs and keys generated above to git for non-production purposes if a quick standalone setup is preferred. Alternatively, one may store these to an external secret store such as Vault, and get these dynamically injected during runtime. See optional Vault integration below.

Background:

Cryptographic keys clearly qualify as sensitive data. Certificates, Certificate Signing Requests and similar files are inherently environment specific, while application configuration is predominantly stage agnostic within the same project. Although certificates (public keys) could be stored within git without a security concern, it may be more manageable to handle private keys and certificates together, via Vault or a similar secret store. The same vehicle that can store private keys outside of git and inject these at runtime can also be used to store and inject certificates.

The following concept is implemented for all files related to x509 certificates:
- it is supported, but not required to store certificates (and keys) in git
- no certificates, key, CSRs etc. is included in configmaps
- certificates and related files to stored to dedicated k8s secrets (opaque cert-secrets)
- projected volumes are used to merge the contents of cert-secrets and configmaps
- projected volumes mounted to existing directories to maintain compatibility
- conditional template rendering allows to selectively enable external secrets for such cert-secrets

### Deploy

An image pull secret is needed with included connection parameters to the image repository to be used. This required information can be provided via one of the three options:
- Pass parameters via a yaml file based on which the image pull secret will be generated and deployed (do not store this file in git)
- Use external secrets for Vault integration (see details below)
- Set up manually in k8s and configure as externally managed (set `general.install.externalSecret.regcred` to `true` in `values-config.yaml`)

As the last step before deployment, additional sensitive data which should not be put under version control needs to be dealt with. This includes middleware and platform credentials and may also include the cipher key used for encrypting sensitive data in files and LDAP, which can be dynamically injected by version 2.2.0 or later.

There are four alternative approaches to handling credentials:
- Provide sensitive data in file `secrets.yaml` manually, use `secrets.yaml.envsubst` as template
- Use a bundled script `secrets-setup.sh` to automatically generate `secrets.yaml` with random data
- Use external secrets for Vault integration
- Set up manually in k8s and configure as externally managed (set `general.install.externalSecret.*creds` to `true` in `values-config.yaml`)

#### Deploying the image pull secret

Specify the image pull secret to be used for downloading container images, adjust `regcred.yaml`. K8s secret `regcred` is generated via a special helm template unless configured as externally managed:
- supports multiple repos in the same Secret with separate credentials for each
- input uses the structure of dockerconfigjson, but without the redundant `auth`
- `auth` properties will be dynamically injected for all repo entries
- sample config provided for IBM Container Registry and local repo, see `regcred.yaml`
- abort with an appropriate error message if no repo entry is configured

#### Autogenerate random passwords and data encryption key

The script `secrets-setup.sh` can be used create `secrets.yaml` with random generated passwords and a random 128 bit Data Encryption Key. Generated passwords consist of 16 characters from the base64 alphabet to avoid issues with special characters. Password complexity rules of the middleware components are considered, specifically, the LDAP admin password is randomly generated until it fulfills the following password policies: minLength 8, minAlpha 2, minOther 2, maxRepeated 2. This script is geared towards developers who need to quickly setup a reasonably secure development environment, but may be useful during the initial setup of environments which prefer to manage secrets internally, or where secrets are later moved to an external vault such as HashiCorp Vault.

#### Vault integration via External Secrets (optional)

Interoperability with Vault is achieved via the use of External Secrets. The External Secrets Operator interacts with [HashiCorp Vault](https://www.vaultproject.io/), [IBM Cloud Secrets Manager](https://www.ibm.com/cloud/secrets-manager) or external secret management systems like [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/), [Google Secrets Manager](https://cloud.google.com/secret-manager), [Azure Key Vault](https://azure.microsoft.com/en-us/services/key-vault/), [CyberArk Conjur](https://www.conjur.org/).

The optional Vault interoperability can be configured via `general.install.externalSecret` selectively for various credentials, image pull secret and x509 keys and certificates, and is disabled by default.

The following secrets can be individually toggled via `general.install.externalSecret.*`:
- `mqcreds`, `oidccreds` and `extcreds`: MQ, OIDC and platform credentials, support external secrets since 2.1.2
- `regcred`: image pull secret, supports external secrets since 2.1.2, can be actively managed since 2.2.5
- `isvdcerts`: since 2.3.3, enables externalization of LDAP key and certificate along with trusted certificates
- `isvdcred`: stores LDAP admin credentials, can be configured as external secret since 2.3.3
- `isvdicerts`: as of version 2.3.3, enables externalization of ISVDI key and certificate along with trusted certificates
- `isvgimcerts`: includes all files under the cert directory, which can be sourced from vault since 2.3.3
- `mqcerts`: since 2.3.3, allows the use of external secrets for MQ key and certificate plus trusted CA certs
- `pgcerts`: allows the use of external secrets for Postgres key and certificate, available since 2.3.3
- `pgcreds`: enables externalization of DB and DB Admin credentials since 2.3.3
- `metricscreds`: enables liberty metrics credentials to be provided externally since 2.3.7

Note:
- configuring `isvdcerts` and `isvdcred` as external secrets only makes sense if `general.install.deployLdap` is enabled
- similarly, enabling an external secret for `isvdicerts` is only effective if ISVDI is deployed by the helm chart (`general.install.deployIsvdi`)
- setting `pgcerts` and `pgcreds` to `true` will not have no effect unless `general.install.deployDb` is also enabled

Integration with Vault or another secret management systems is documented in detail [here](docs/VAULT.md).

#### Post-deployment steps

When installing from scratch, schema and initial data have to be loaded to both DB and LDAP, with external data tier as well as data tier deployed via the helm chart. This is not seen as a responsibility or an integral step of the helm chart itself, as there are valid scenarios where IVIG has to be deployed or redeployed with an existing data tier containing data which must not be erased (migration, disaster recovery, upgrade scenarios). This requires finer grained control over the data initialization process.

Similarly, version upgrades (fixpacks, but not interim fixes) may include schema extensions and specific logic to convert from the existing to the new data formats. Experience has shown that DB or LDAP schema or data upgrade code shipped with the fixpacks of the product is often defective or incomplete and requires manual actions to successfully complete.

Therefore, version 2.2.3 and newer provides tooling for automation, but does not unconditionally invoke `dbConfig.sh` and `ldapConfig.sh` within the container.

On a fresh install, one could trigger DB and LDAP schmema and data setup as soon as `isvgim` is up and running, then restart:
```
kubectl -n $NAMESPACE wait --for=condition=Ready --timeout=5m pod -l app=isvgim
kubectl -n $NAMESPACE exec isvgim-0 -- /bin/bash -c "/work/util/extract-config-response.sh --install && /work/ldapConfig.sh install && /work/dbConfig.sh install"
kubectl -n $NAMESPACE rollout restart sts/isvgim
```

For schema & data upgrade between versions one would scale down `isvgim`, then call the upgrade logic from within the config container `isvgimconfig` (which is started for this purpose only and then terminated):
```
kubectl -n $NAMESPACE scale deploy/isvgimconfig --replicas 1
kubectl -n $NAMESPACE scale sts/isvgim --replicas 0
kubectl -n $NAMESPACE exec deploy/isvgimconfig -- /bin/bash -c "/work/util/extract-config-response.sh --upgrade && /work/ldapConfig.sh upgrade && /work/dbConfig.sh upgrade $OLD_VERSION"
kubectl -n $NAMESPACE scale deploy/isvgimconfig --replicas 0
kubectl -n $NAMESPACE scale sts/isvgim --replicas 1
```

#### Common tasks

When working directly with `helm` rather than via ArgoCD (which is a viable option for both Developers/Integrators and for team who have not adopted a full CI/CD solution for GitOps-driven Kubernetes) see the following list of commands which illustrate various DevOps tasks.

```
# Development/integration

# inspect the output of a single template (from within the smarterkit directory)
helm template --dry-run=client -f values.yaml -f values-config.yaml -f secrets.yaml -f regcred.yaml -s templates/201-deployment-isvgimconfig.yaml .
# split output into separate files for each template and store to output-dir for inspection/debugging
helm template --dry-run=client --output-dir output-dir -f values.yaml -f values-config.yaml -f secrets.yaml -f regcred.yaml .

# Normal operation

# compare desired state with currently deployed state
helm template --dry-run=client -f values.yaml -f values-config.yaml -f secrets.yaml -f regcred.yaml --set revision=$(git log -n 1 --pretty=format:%h) . | kubectl diff -f -
# enforce desired state
helm template --dry-run=client -f values.yaml -f values-config.yaml -f secrets.yaml -f regcred.yaml --set revision=$(git log -n 1 --pretty=format:%h) . | kubectl apply -f -
```

### Install Verification Test

The first fundamental check is to log on to IVIG and list users.

Execute smoke tests for your IVIG project as necessary. (Smoke tests are a subset of test cases that cover the most important functionality of a component or system, used to aid assessment of whether main functions of the software appear to work correctly.)

### Troubleshooting guide

~When using the demo setup script `secrets-setup.sh`, please note that GNU grep 3.6 (from 2020, shipped with CentOS 9) yields abnormal behavior. Use a more recent version of grep (see section [Components and Dependencies](#components-and-dependencies)).~ This issue is resolved with version 2.3.3.

Should errors occur after deployment, review K8s events and IVIG application logs:
```
kubectl events -n <namespace>

kubectl logs -n <namespace> isvgim-0 -c logs-im
```
Check the availability and configuration of your database and LDAP instance.

Note that there should not be any additional files under the certificate directory (`smarterkit/config/certs` by default), the presence of binary files is known to yield abnormal helm template rendering.

### Hardening

This project delivers many [extras not included in the original product](docs/EXTRAS.md) which are mostly geared towards enhancing security:
- Redesigned, more secure approach to working with sensitive data
  - Proper separation of sensitive and non-sensitive data
  - Dynamic credential injection
  - Improved protection of data encryption keys
  - Interoperability with external secret management systems such as HashiCorp Vault
- Custom flags for selectively enabling general hardening measures
- Fixes of bugs which impact security but have not been addressed in the original product yet

## Setup guide - ArgoCD

The repository setup and configuration steps described in the standalone setup guide applies to this scenario as well.

On high level, the following sequence of steps should be followed:
- Check out this project, adjust `values.yaml` and `values-config.yaml` for your environment and check into your git
- Generate x509 certificates offline (or in another environment) and store these to git
- Adjust the application manifest sample in the root directory of this project (use external or internal vault)
- Enable automatic sync or sync manually via ArgoCD

In a real-life setup, the typical pattern is to deploy multiple environments (such as development, test and production) from a single Git repository. A separate guide describes the [recommended approach for a multi-stage project via Argo CD](docs/ARGO-CD.md).

## Future plans

This section contains near and mid term plans, uncommitted feature candidates and general information about the future of the project.

### Features under consideration

- ~config property `general.install.externalSecret` to control if credentials will be managed via helm chart or externally~ DONE
- ~move pre-init logic to a separate init container~ DONE
- ~eliminate the need to store `isvgimks` by initializing one on-the-fly during initialization~ DONE
- ~optional/modular deployment of postgres DB and LDAP into the same namespace for demo or development~ DONE
- ~convenience utility for DB and LDAP upgrade and initial schema and data load~ DONE
- ~credentials from external secrets (optional, selectively configurable)~ DONE
- ~x509 certificates and key from external secrets (optional, selectively configurable)~ DONE
- ~HashiCorp Vault integration walkthrough~ DONE

## Further Documentation

This section points the reader to further documentation within the repository (resources in the `docs` folder) or outside of the repository.

- [Introductory Presentations](https://ibm.ent.box.com/folder/335821059835?s=gpwqalbj81ku5tc67rqdc6r2etqse862)
- [Guidelines for Contributors](docs/CONTRIBUTING.md)
- [Changelog](CHANGES.md) 
- Marketing flyers, Offering and Asset Information
- Demos: see the `demo` branch here in git (or any of the `demo-x.y.z` branches for particular versions).

## Contacts

Tibor Bősze <tibor.boesze@nospam.ibm.com>

*This project is supported on a best effort basis by the contributors in spare
time. Issues should be reported via GitHub. Maintenance and development of
enhancements may be provided on a commercial basis, depending on the
availability of the project team.*

