# IVIG Declarative Deployment setup guide - pure Helm

This project delivers an alternative deployment method for IBM Verify Identity Governance for GitOps-driven K8s environments. At the core, a Helm chart implements the deployment logic. It can be deployed without using any third party component other than Helm - this approach, referred to as a **pure Helm standalone setup** is covered in this guide. Separate documentation covers the [setup with Argo CD](ARGO-CD.md), a higher level deployment tool. Readers are encouraged to process this documentation first as other documentation builds on the information captured in this guide.

The pure Helm setup is a viable option for both Developers/Integrators and for teams who have not adopted a full CI/CD solution for GitOps-driven Kubernetes. This setup requires Git, the user will directly interact with `helm` (rather than indirectly via Argo CD) and `kubectl`. The fastest way to get up and running is a minimal pure-Helm setup.

## System Requirements

Strictly speaking, the only third party dependency is Helm, version 3.18 or newer. Therefore any continuous delivery platform which supports Helm should be supported but explicit testing was done on Argo CD only.

There are no specific system requirements other than [those of the IVIG version, which will be deployed](https://www.ibm.com/software/reports/compatibility/clarity/index.html?name=IBM%20Verify%20Identity%20Governance). Use a Kubernetes release which has not reached end-of-life yet.

Optional [Integration with Vault via External Secrets](VAULT.md) has additional dependencies [documented separately](VAULT.md#prerequisites).

### Optional user convenience scripts

There are optional user convenience scripts which can be used for quickly setting up a demo or development environment. These scripts have been specifically developed with efficiency and minimal dependencies in mind and are known to work with the following versions of standard Linux/Unix utilities:
- `cert-setup.sh`: bash 3.2, sed (GNU 4.2, BSD)
- `cert-util.sh`: bash 3.2, OpenSSL 3
- `secrets-setup.sh`: bash 3.2, grep (GNU 3.6, BSD 2.6), OpenSSL 3

Note: Although GNU/Linux is the primary target platform, there is at least one user of this project who runs MacOS. The current version of MacOS still ships with an extremely outdated bash version (3.2.57 from 2007) due to GPLv3 licensing issues. Convenience scripts of version 2.3.4 are compatible with this old bash version as well as BSD sed and grep.

## TL;DR

This section is intended for users intimately familiar with IVIG, Kubernetes and Helm. It provides quick-start instructions in a compact and minimalistic fashion. It is recommended to read and understand the complete setup guide which covers technical details and deployment options.

### Quick demo

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

### Recommended standalone setup

**Warning:** Users are encouraged to read the documentation carefully and be mindful when adjusting configuration. For less experienced users it is recommended to start with deploying a simple configuration first, and then increasing complexity in small iterations. Beyond ensuring correct syntax of configuration files, understanding the semantics of the configuration and avoiding logical errors is key, e.g. if you mark a component to be externally managed (enable external secrets), do not expect it to be automatically created, but ensure it is correctly provisioned upfront.

The minimal setup described above could deploy an ephemeral demo environment within minutes, but note that essential data is only stored locally, not committed to a Git repository. The recommended pure Helm approach requires setting up a Git repository to persistently store configuration and provide version control for the deployment.

Users should create their own Git repo and adjust config as needed:
```
# fork the project on GitHub, then clone it and configure upstream
git clone https://github.com/${YOUR_USER}/ivig-declarative-deployment.git
cd ivig-declarative-deployment/smarterkit
git remote add upstream https://github.com/ibm-verify/ivig-declarative-deployment.git
# create a demo branch and switch to it
git checkout -b demo-xyz
# adjust values.yaml and values-config.yaml as needed
vi values-config.yaml values.yaml
# NOTE: when committing to a public Git repo, move general.license section of
# values-config.yaml to a separate file (license.yaml) which you do not commit
git add values-config.yaml values.yaml
git commit -m "init quick demo"
# generate certs
./cert-setup.sh
# option A: store certs to Git for a developer setup (simpler)
git add config/certs/*
git commit -m "quick demo certs"
# option B: do not store certs to Git, maybe import to vault later (more secure)
```

Generate secrets (not to be stored in Git), then deploy to K8s and initialize data tier:
```
# autogenerate random secrets
./secrets-setup.sh
# OPTIONAL: if you created a separate license.yaml file (e.g. public Git repo)
cat license.yaml >> secrets.yaml && rm license.yaml
# deploy desired state
helm template --dry-run=client -f values.yaml -f values-config.yaml -f secrets.yaml -f regcred.yaml --set revision=$(git log -n 1 --pretty=format:%h) . | kubectl apply -f -
# init data tier
kubectl -n $NAMESPACE wait --for=condition=Ready --timeout=5m pod -l app=isvgim
kubectl -n $NAMESPACE exec isvgim-0 -- /bin/bash -c "/work/util/extract-config-response.sh --install && /work/ldapConfig.sh install && /work/dbConfig.sh install"
kubectl -n $NAMESPACE rollout restart sts/isvgim
```
Wait for the application to start and then print out the login URL:
```
kubectl -n $NAMESPACE wait --for=condition=Ready --timeout=5m pod -l app=isvgim && \
kubectl -n $NAMESPACE get pod/isvgim-0 -o jsonpath='Login at https://{.status.hostIP}:' && \
kubectl -n $NAMESPACE get svc/isvgim -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}{"/itim/console\n"}'
```

The [section on troubleshooting](#troubleshooting) provides guidance on diagnosing and resolving errors.

## Prerequisites
- K8s cluster up and running
- ~namespace and registry pull secret configured~ (chart 2.2.5 will deploy the namespace and optionally the pull secret as well)
- data tier ready and available if using an external data tier (chart 2.2.1 enables optional deployment of DB and LDAP intended for non-production use)

**Note:** Deployments of ISVDI scaled up to 2 or more pods require a storage class supporting `ReadWriteMany` access mode. A simple setup for demo or development purposes will work fine with `ReadWriteOnce` as long as ISVDI is not scaled up.

## Repo setup

As a first step, check out this project from GitHub or even better, fork it to create your own project specific repo. Then adjust Helm Values and generate certificates.

### Fork

A fork is a repository that starts as a copy of another repository, the original repository used as source is called the upstream repository. A fork acts as an independent duplicate of upstream (someone else's repository), allowing you to make modifications without affecting the original project, but with the ability to receive updates from the upstream repository.

Many hosting platforms (like GitHub or GitLab) offer a simple "Fork" and "Sync	fork" button but only support forking within their own ecosystem and certain provider or plan specific restrictions may apply. Due to the decentralised nature of Git, one can achieve the exact same result from the command line via native Git capabilities, without the provider specific restrictions, allowing one to fork a repo one has access to, to another repo, regardless of the hosting platforms involved, for example:
- Fork a GitHub repo to a self hosted or corporate GitLab instance (or vice versa)
- Fork a GitHub repo to an organisation's GitHub Enterprise Server (or the other way around)
- Fork a public GitHub repo to a private GitHub repo (which GitHub does not allow to perform via the Web UI)
- Fork any accessible repo to a server-side Git repo (raw SSH Git server)

**Note:** Teams looking into deploying IVIG into a GitOps driven K8s environment will most likely already have their own infrastructure to create and manage Git repositories, such as a private GitLab instance or as a bare minimum a local server exposing Git repos over SSH. While it is easy and convenient to start with GitHub, it is certainly not the only option available. A real-life project will typically utilize whatever Git infrastructure the target environment already uses.

Using the simple "Fork" button on the Web UI:
1. Navigate to the root of this repository via web browser
2. In the top-right corner of the page, click the "Fork" button
3. Review and press the "Create fork" button
4. Once the fork is created, clone it and configure upstream
   ```
   git clone https://github.com/${YOUR_USER}/ivig-declarative-deployment.git
   cd ivig-declarative-deployment
   git remote add upstream https://github.com/ibm-verify/ivig-declarative-deployment.git
   ```

The universal alternative that allows forking to any enterprise, on-prem or self-hosted Git:
```
# create an empty repository on the preferred provider, clone and add upstream
git clone https://git.example.com/foobar/ivig-declarative-deployment.git
cd ivig-declarative-deployment
git remote add upstream https://github.com/ibm-verify/ivig-declarative-deployment.git
# propagate the master branch from the upstream to the new repository
git pull upstream master
git push origin master
```

### Helm Values configuration

Next, adjust `values.yaml` and `values-config.yaml` for your environment and store them to your Git project. Users unfamiliar with the product may run `starterkit/bin/configure.sh -manual` after downloading and unpacking the original starterkit bundled with the product. The command will generate `config.yaml` which may then be used as a baseline for `values-config.yaml`, as these files follow the same structure with minimal deviations. Keep the following in mind:

- Adjust `values.yaml`:
    - `namespace`, `timezone`, `licenseType`, `storage.className` and `storage.mode` are only read from `smarterkit/values.yaml`, define them there!
    - `clusterUrl` is set to the Kubernetes API server internal endpoint, leave it as-is!
- If you decide to use `starterkit/bin/configure.sh -manual` to generate `config.yaml` then just copy the content to `values-config.yaml` and adjust as follows:
    - `general.install`: it is advised to only retain properties which are defined in the bundled `values-config.yaml`, others are not used
    - `general.install.enableAuditLog`: it is not read from `values-config.yaml`, remove it and use `services.isvd.auditlog` defined in `smarterkit/values.yaml`
    - `general.install.externalSecret`: while it is not supported by the original starterkit and therefore absent in `config.yaml`, use this to selectively mark MQ, OIDC or platform credentials as externally managed (requires manual setup of the secrets or Vault integration via External Secrets Operator)
    - `externalRegistry`: it is not supported - it will not cause any error but it is recommended to remove this section to avoid confusion
    - `server.truststore`: as `starterkit/bin/configure.sh -manual` may leave it empty or incomplete, make sure there is at least the list item `  - '@isvgimRootCA.crt'` present
    - `server.flags.enableFIPS`: it is advised to delete it, as it is not read from `values-config.yaml`, but dynamically initialized based on `fips` defined in `smarterkit/values.yaml`
    - `oidc`: while this section is not generated by the original starterkit and therefore absent in the generated `config.yaml`, we support it and the same instructions apply for OIDC setup (if you already configured OIDC in one of your deployments, just append the `oidc` section to `values-config.yaml`
- If you are familiar with the structure of `values-config.yaml`, edit it directly
    - `general.license`: as a minimum, fill in `activationKey` and set `accepted` to `true`; add license keys for LDAP and Directory Integrator if you wish to deploy these
    - the bundled file will deploy an internal data tier and Directory Integrator by default, adjust the file as required

#### Do not store license keys in public repositories

While storing license data and activation keys in a private or tightly controlled corporate Git repository would be generally fine, some might prefer to not store such information under version control at all. When working with a publicly accessible Git repository, ensure that licensing data and activation keys are not disclosed. This section describes how leaking license keys can be avoided by not storing such information under version control.

Instead of providing license keys in `values-config.yaml` which is stored in Git, one can leave all values under `general.license` in that file blank and specify these values in a separate file that will be passed to the `helm` command but not stored in Git. When migrating from a classic installation, move the `general.license` section of `config.yaml` to a separate file, do not include it in `values-config.yaml`.


The example below demonstrates how a separate file `license.yaml` capturing license acceptance and activation key along with LDAP and Directory Integrator license keys is created.
```
cd ivig-declarative-deployment/smarterkit
cat <<EOF>> license.yaml
general:
  license:
    activationKey: XXAZ6-Z7O6E-H6DUA-Y1PBZ-5RS5X
    accepted: true
    ldapKey: R2VuDGJSa0vqJH01+JKryHts2dRZy/8aCH0k2wq1Rxp3q/A36a5Uei4D...JWs=
    isvdiKey: UmVCYBaU+QRpmAtuTNp2VaUACVH29SCmgHeR9YGanL9tyPRmzmMmHRbF...ATw=
    isvartKey:
    riskKey:
EOF
```

Keep in mind to replace the sample/dummy values with your actual license keys before deployment.

Make sure these additional values are included when the `helm` command is run.
- *Option A:* Once you created the `secrets.yaml` file (a step documented later in this guide), append license data to it via `cat license.yaml >> secrets.yaml && rm license.yaml` and then, the command line invocation of `helm` does not need to be adjusted.
- *Option B:* Amend the `helm` command invocation with `-f license.yaml` so this additional file will also be used to read values from.


#### Optional advanced database configuration via explicit JDBC URL

Declarative deployment increases flexibility and robustness of JDBC configuration beyond what the original product supports. It reads and writes the JDBC URL formats the core product supports with a compatible logic, and additionally offers a new configuration parameter `db.forcedJdbcUrl` in `values-config.yaml` to explicitly set a JDBC connection string rather than providing hostname, port and database name. This allows automated deployment with advanced database configuration (such as load balancing and failover) from scratch, which is not offered by the original product.

Via `db.forcedJdbcUrl` one might specify the JDBC connection using the following formats and advanced features:
- Oracle Thin Driver (basic SID style)
- Oracle Thin-Style Service Name (preferred modern syntax)
- Oracle Net Connection Descriptor - Full explicit descriptor
    - with SID or Service Name
    - explicit SSL configuration
    - multiple addresses, RAC, load balancing and failover
    - timeouts and other advanced parameters
- DB2 Type4 Driver extra parameters
    - TLS version and cipher suite selection
    - high availability (HADR), failover and client reroute (ACR)
    - performance optimisation
    - many more advanced parameters
- Postgres Driver extra parameters
    - multiple hosts, failover and load balancing, read scaling
    - many more advanced parameters

### Bundled convenience scripts for x509 certificates

The next step is to generate x509 certificates offline (or in another environment). Two openssl-based alternatives are bundled, but of course, one may use any other means to generate certificates.

The `cert-util.sh` script is added to create, renew and list certificates for a configurable set of components. The structure of the certificates is intentionally kept compatible with the original starterkit, but the logic for managing certificates has been externalized, it does not run within the container.

The logic is implemented such that existing cryptographic keys and certificate signing requests are reused when creating or renewing certificates.

Subject alternate names (domain names) are configured according to the requirements of each component, inline with how the original starterkit would create certificates.

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

As an alternative, another script, `cert-setup.sh` is included to auto-detects the part of configuration that is relevant for certificates, once `values.yaml` and `values-config.yaml` have already been adjusted. In particular, it will retrieve the K8s namespace from `values.yaml`, collect extra hostnames (which should be added to the certificate of IVIG server) and the list of optional components to be deployed from `values-config.yaml`. This script, after collecting the information required, will invoke `cert-util.sh` to create certificates, and after that, to list the details of the certificates created.

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

### Tips and tricks for certificate creation

One can use `cert-util.sh` to conveniently create additional certificates with arbitrary subject alternate names, signed by `isvgimRootCA`. This is useful when additional certificates need to be created for external data tier components or other components of the target environment, where typically finer grained control over subjectAltNames is also required. The example below demonstrates, how to create a certificate for `foo` and control subject alternative names via the environment variable `FOO_ALTNAME`.

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

### Storing certificates and related files

One may store the certificates, CSRs and keys generated above to Git for non-production purposes if a quick standalone setup is preferred. Alternatively, one may store these to an external secret store such as Vault, and get these dynamically injected during runtime. See optional Vault integration below.

Background:

Cryptographic keys clearly qualify as sensitive data. Certificates, Certificate Signing Requests and similar files are inherently environment specific, while application configuration is predominantly stage agnostic within the same project. Although certificates (public keys) could be stored within Git without a security concern, it may be more manageable to handle private keys and certificates together, via Vault or a similar secret store. The same vehicle that can store private keys outside of Git and inject these at runtime can also be used to store and inject certificates.

The following concept is implemented for all files related to x509 certificates:
- it is supported, but not required to store certificates (and keys) in Git
- no certificates, key, CSRs etc. are included in configmaps
- certificates and related files are stored to dedicated K8s secrets (opaque cert-secrets)
- projected volumes are used to merge the contents of cert-secrets and configmaps
- projected volumes mounted to existing directories to maintain compatibility
- conditional template rendering allows to selectively enable external secrets for such cert-secrets

## Deploy

An image pull secret is needed, it includes connection parameters to the image repository to be used. This required information can be provided via one of the three options:
- Pass parameters via yaml file `regcred.yaml` based on which the image pull secret will be generated and deployed (do not store this file in Git if it contains sensitive data)
- Use external secrets for Vault integration (see details below)
- Set up manually in K8s and configure as externally managed (set `general.install.externalSecret.regcred` to `true` in `values-config.yaml`)

As the last step before deployment, additional sensitive data which should not be put under version control needs to be dealt with. This includes middleware and platform credentials and may also include the cipher key used for encrypting sensitive data in files and LDAP, which can be dynamically injected by version 2.2.0 or later.

There are four alternative approaches to handling credentials:
- Provide sensitive data in file `secrets.yaml` manually, use `secrets.yaml.envsubst` as template
- Use the bundled script `secrets-setup.sh` to automatically generate `secrets.yaml` with random data
- Use external secrets for Vault integration
- Set up manually in K8s and configure as externally managed (set `general.install.externalSecret.*creds` to `true` in `values-config.yaml`)

### Deploying the image pull secret

Specify the image pull secret to be used for downloading container images, adjust `regcred.yaml`. K8s secret `regcred` is generated via a special Helm template unless configured as externally managed:
- supports multiple repos in the same Secret with separate credentials for each
- input uses the structure of dockerconfigjson, but without the redundant `auth`
- `auth` properties will be dynamically injected for all repo entries
- sample config provided for IBM Container Registry and local repo, see `regcred.yaml`
- abort with an appropriate error message if no repo entry is configured

### Autogenerate random passwords and data encryption key

The script `secrets-setup.sh` can be used create `secrets.yaml` with random generated passwords and a random 128 bit Data Encryption Key. Generated passwords consist of 16 characters from the base64 alphabet to avoid issues with special characters. Password complexity rules of the middleware components are considered, specifically, the LDAP admin password is randomly generated until it fulfills the following password policies: minLength 8, minAlpha 2, minOther 2, maxRepeated 2. This script is geared towards developers who need to quickly setup a reasonably secure development environment, but may be useful during the initial setup of environments which prefer to manage secrets internally, or where secrets are later moved to an external vault such as HashiCorp Vault.

### Vault integration via External Secrets (optional)

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
- similarly, enabling an external secret for `isvdicerts` is only effective if ISVDI is deployed by the Helm chart (`general.install.deployIsvdi`)
- setting `pgcerts` and `pgcreds` to `true` will not have no effect unless `general.install.deployDb` is also enabled

Integration with Vault or another secret management system is documented in detail [here](VAULT.md).

### Enabling inbound connections from the outside

There are different ways one can expose a K8s service to the outside world, using a NodePort is one of them, which is fine for a demo/simple setup, but defining an Ingress would be a more typical way for a real-life production deployment.

#### Via NodePort by default

The default behavior is to expose the application via a NodePort: Every node in the cluster configures itself to listen on a specific port and to forward traffic to one of the ready endpoints associated with that Service. One can reach the application from outside the cluster, by connecting to any node using the appropriate protocol and port, in this case HTTPS and the port configured via `services.isvgim.ports.node` in `values.yaml`.

Although the application could be reached via the IP of any node, the command used in this guide always generates an URL that points to the node the first pod of the isvgim StatefulSet is running on. This approach consistently works on small and large clusters. The HTTPS port is also dynamically queried to ensure the URL is correctly generated.
```
kubectl -n $NAMESPACE wait --for=condition=Ready --timeout=5m pod -l app=isvgim && \
kubectl -n $NAMESPACE get pod/isvgim-0 -o jsonpath='Login at https://{.status.hostIP}:' && \
kubectl -n $NAMESPACE get svc/isvgim -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}{"/itim/console\n"}'
```

#### Via Ingress

An Ingress is a Kubernetes resource that routes external HTTP/HTTPS traffic to internal services. An Ingress Controller is a reverse proxy that watches the Kubernetes API and automatically configures routing rules based on your Ingress definitions. Traefik is a popular choice.

Key benefits for large-scale deployments:
- Security Hardening: Network access to the cluster nodes from the outside can be restricted to a single, tightly controlled secure channel
- Cost Efficiency: Route thousands of microservices through a single cloud load balancer IP instead of using a unique balancer per service.
- Dynamic Configuration: Traefik natively watches the Kubernetes API to update routing tables in real-time without restarts when pods scale or services change.
- Built-in Features: Handle SSL/TLS automation, path-based routing, rate limiting, and request middleware right at the cluster edge.

While configuration of an Ingress Controller is outside of the scope of this documentation, the following Helm template shall provide inspiration and a solid starting point for a traefik-based ingress with the following features:
- Session affinity via a properly secured and automatically managed HTTP cookie
- Traefik reverse proxy will skip backend certificate checks such as CA and hostname verification (it uses the cluster-internal hostname to access the backend which would typically not be registered in the certificate as a subject alternate name)
- Automatic creation of SSL/TLS certificate for the hostname configured
- Routes inbound HTTPS traffic based on hostname (Server Name Indication during SSL handshake) to the right service

```yaml
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: skipverify
  namespace: {{ .Values.namespace }}
spec:
  insecureSkipVerify: true
---
apiVersion: v1
kind: Service
metadata:
  name: isvgim-traefik
  namespace: {{ .Values.namespace }}
  annotations:
    traefik.ingress.kubernetes.io/service.serversscheme: https
    #syntax: <ServersTransport.namespace>-<ServersTransport.name>@kubernetescrd
    traefik.ingress.kubernetes.io/service.serverstransport: {{ .Values.namespace }}-skipverify@kubernetescrd
    traefik.ingress.kubernetes.io/service.sticky.cookie: "true"
    traefik.ingress.kubernetes.io/service.sticky.cookie.httponly: "true"
    traefik.ingress.kubernetes.io/service.sticky.cookie.name: idm-stateful
    traefik.ingress.kubernetes.io/service.sticky.cookie.secure: "true"
spec:
  selector:
    app: isvgim
  ports:
    - name: https
      port: {{ .Values.services.isvgim.ports.https }}
      protocol: TCP
      targetPort: {{ .Values.services.isvgim.ports.https }}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: isvgim-ingress
  namespace: {{ .Values.namespace }}
spec:
  ingressClassName: traefik
  rules:
    - host: {{ first .Values.server.hostname }}
      http:
        paths:
          - backend:
              service:
                name: isvgim-traefik
                port:
                  number: {{ .Values.services.isvgim.ports.https }}
            path: /
            pathType: Prefix
  tls:
    - hosts:
        - {{ first .Values.server.hostname }}
      secretName: isvgim-tls
```

### Configuring metadata injection

The ability to dynamically inject metadata into Helm templates allows turning static templates into highly adaptable infrastructure. Label and annotation injection centralizes metadata management, ensuring environment consistency and driving cross-system automation without hardcoding project specific metadata in Helm templates. Dynamically injecting these key-value pairs enables third-party tools to auto-discover resources, seamlessly route traffic via Ingress, or acts as the foundation for centralized log management by tagging log sources with environments, teams, or application names.

Dynamic injection of Kubernetes labels and annotations is supported into both pods and services and can be configured via `extra.annotations` and `extra.labels` in `values-config.yaml` (or any Values file included in your setup).

One can select any of the following Kubernetes resources and define extra annotations and labels to be injected without modifying the Helm templates.
- Services
    - hazelcast-headless
    - isvdi
    - isvgim
    - mq-headless
    - mqshare
- Pod templates of deployments and stateful sets
    - isvgim
    - isvdi
    - mqshare

The following example would be appended to `values-config.yaml` to enable the discovery of monitoring endpoints by the popular monitoring tool prometheus and to hint centralized log management to correctly tag and parse log sources (assuming prometheus and fluentbit are up and running and configured for this use case).

This is achieved by defining
- static annotations to be added to the pod templates of `deployment isvdi` and `statefulset isvgim`
- string template for rendering annotations for the service `isvgim`, and reference the port number from within the template
- string template to add pod labels for `isvdi` in this specific case including the environments name dynamically, along with a static label `app.kubernetes.io/component`

```yaml
extra:
  annotations:
    pod:
      # hint log sources and parser for centralized log management via fluentbit
      isvgim:
        fluentbit.io/tag: "idm-server-logs"
        fluentbit.io/parser: "multiline-custom-xml"
      isvdi:
        fluentbit.io/tag: "idm-adapter-logs"
        fluentbit.io/parser: "multiline-regex-or-log4j"
    service:
      # instruct monitoring tool prometheus to scrape data from the service
      isvgim: |-
        prometheus.io/scrape: "true"
        prometheus.io/port: {{ .Values.services.isvgim.ports.https }}
        prometheus.io/path: "/metrics"
  labels:
    pod:
      # assuming the values file for your production environment defines
      #   environment: production
      # this template string would dynamically render to
      #     app.kubernetes.io/component: adapters
      #     env: production
      isvdi: |-
        app.kubernetes.io/component: adapters
        env: {{ .Values.environment }}
```

**Keep in mind:** While the ability to inject metadata dynamically opens up an unrestricted set of integration options, this feature does not implement any integration per se. It is a future-proof approach with high potential but always depends on third-party tools, platforms or services to be present and configured appropriately as a prerequisite.

### Post-deployment steps

When installing from scratch, schema and initial data have to be loaded to both DB and LDAP, with external data tier as well as data tier deployed via the Helm chart. This is not seen as a responsibility or an integral step of the Helm chart itself, as there are valid scenarios where IVIG has to be deployed or redeployed with an existing data tier containing data which must not be erased (migration, disaster recovery, upgrade scenarios). This requires finer grained control over the data initialization process.

Similarly, version upgrades (Fixpacks, but not Interim Fixes) may include schema extensions and specific logic to convert from the existing to the new data formats. Experience has shown that the automated DB or LDAP schema and data upgrade logic shipped with the Fixpacks of the product is often incomplete and requires manual actions to successfully finish the upgrade.

Therefore, version 2.2.3 and newer provides tooling for automation, but does not unconditionally invoke `dbConfig.sh` and `ldapConfig.sh` within the container.

On a fresh install, one could trigger DB and LDAP schema and data setup as soon as `isvgim` is up and running, then restart:
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

### Common tasks

When working directly with `helm` rather than via Argo CD (which is a viable option for both Developers/Integrators and for teams who have not adopted a full CI/CD solution for GitOps-driven Kubernetes) see the following list of commands which illustrate various DevOps tasks.

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

## Install Verification Test

The first fundamental check is to log on to IVIG and list users.

Execute smoke tests for your IVIG project as necessary. (Smoke tests are a subset of test cases that cover the most important functionality of a component or system, used to aid assessment of whether main functions of the software appear to work correctly.)

## Troubleshooting

Many errors stem from human factors such as providing wrong configuration and skipping over or inaccurately executing required steps. Some users will intentionally alter and tailor the deployment method to fit their specific needs but introduce inconsistencies by incomplete or flawed changes.

While users are free to customize the Helm templates and other resources in this project, it is the sole responsibility of the user to investigate and eliminate undesired side effects of any modification. For example, renaming containers or other K8s resources, rearranging the order of containers within pods will require adjustments to the commands listed in this guide or even the overall procedure described.

### General Diagnostics

Should errors occur after deployment, review K8s events and IVIG application logs:
```
kubectl events -n $NAMESPACE
kubectl logs -n $NAMESPACE isvgim-0 -c logs-im
kubectl logs -n $NAMESPACE sts/isvgim -c logs-im
```
Check the availability and configuration of your database and LDAP instance.

### Unable to login on a fresh deployment

A typical reason for not being able to login is that the user forgot or failed to initialize the data tier.

Symptoms:
1. All the containers started without errors
2. Login attempt to IVIG via the login URL fails with the following error displayed on the UI:
   ```
   CTGIMU534E
   Login authentication failure occurred. The specified user ID and password are not valid, have expired, or have been disabled.
   ```
3. The applications logs (output of container `logs-im`) indicate missing objects in the directory server during an authentication attempt:
   ```json
   {
    "type": "ivig_trace",
    "level": "MIN",
    "productId": "CTGIM",
    "component": "com.ibm.itim.apps.challenge",
    "productInstance": "defaultServer",
    "sourceFileName": "com.ibm.itim.apps.challenge.ChallengeResponseHelper",
    "sourceMethod": "getDirectorySystemEntity",
    "exception": "com.ibm.itim.dataservices.model.ObjectNotFoundException: CTGIMF029E The specified object cannot be found in the directory server. The object might have been moved or deleted before your request completed. The following information was returned from the directory server: The dc=ivig object cannot be found with the specified name ivig. at com.ibm.itim.dataservices.model.domain.DirectorySystemSearch.searchById(DirectorySystemSearch.java:142) ..."
   }
   ```

Solution: Make sure the data tier is successfully initialized, as described under [Post-deployment steps](#post-deployment-steps). If data tier initialization is correctly invoked but fails, confirm the availability and configuration of the database and LDAP instance, and verify that connection parameters are correct.

### PVC stuck in pending state

In order to scale up ISVDI to 2 or more replicas, a persistent volume with `ReadWriteMany` access mode is needed. If this access mode is configured via `storage.mode` (e.g. in `values.yaml`) but the configured storage class does not support this mode, the persistent volume claim will be stuck in pending state indefinitely. It is recommended to ensure in advance that access mode `ReadWriteMany` is supported by the selected storage class.

A simple way to check if `ReadWriteMany` access mode is supported by a given storage class is to create a PVC (i.e. `test-rwx-pvc`) with such parameters. If the status changes to "Bound", `ReadWriteMany` is enabled for the storage class. If a status stuck in "Pending" state is observed, run `kubectl describe pvc test-rwx-pvc` and look for a provider specific `ProvisioningFailed` event to confirm the storage provider does not support `ReadWriteMany`. Do not forget to delete the PVC once done.

**Note:** Even with `ReadWriteMany` supported, if the volume binding mode of the storage class is set to `WaitForFirstConsumer`, the PVC will remain in pending state until a pod references it. A temporary helper pod can be used to trigger volume creation.

The snippet below demonstrates the check waiting up to 2 minutes for the PVC to bind. Make sure to substitute `$MY_STORAGE_CLASS` with the actual storage class name.
```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-rwx-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: $MY_STORAGE_CLASS
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-rwx-pvc-binder
spec:
  containers:
  - name: alpine
    image: alpine:latest
    command: ["sleep", "30"]
    volumeMounts:
    - name: test-rwx
      mountPath: /mnt/storage
  volumes:
  - name: test-rwx
    persistentVolumeClaim:
      claimName: test-rwx-pvc
  restartPolicy: Never
EOF

kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/test-rwx-pvc --timeout=2m && echo "SUCCESS" \
  || { echo "FAILED"; kubectl describe pvc test-rwx-pvc; }

kubectl delete pod test-rwx-pvc-binder
kubectl delete pvc test-rwx-pvc
```

### Further Hints

~When using the demo setup script `secrets-setup.sh`, please note that GNU grep 3.6 (from 2020, shipped with CentOS 9) yields abnormal behavior. Use a more recent version of grep (see section [Components and Dependencies](#components-and-dependencies)).~ This issue is resolved with version 2.3.3.

**Note:** There should not be any additional files under the certificate directory (`smarterkit/config/certs` by default), the presence of binary files is known to yield abnormal Helm template rendering.

