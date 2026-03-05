# Changelog

All notable changes to this project will be documented in this file.

## 2.3.3 (2026-03-05)

This version changes the approach how x509 certificates are passed to containers.

Cryptographic keys clearly qualify as sensitive data. Certificates, Certificate Signing Requests and similar files are inherently environment specific, while application configuration is predominantly stage agnostic within the same project. Although certificates (public keys) could be stored within git without a security concern, it may be more manageable to handle private keys and certificates together, via Vault or a similar secret store. The same vehicle that can store private keys outside of git and inject these at runtime can also be used to store and inject certificates.

The following concept is implemented for all files related to x509 certificates:
- remove all certificates, key, CSRs etc. from configmaps
- store certificates and related files to dedicated k8s secrets (opaque cert-secrets)
- define projected volumes to merge the contents of cert-secrets and configmaps
- mount projected volumes to existing directories to maintain compatibility
- apply conditional template rendering to selectively enable external secrets for such cert-secrets

This clean sepration enables vault integration for the following secrets which can be individually toggled via `general.install.externalSecret.*`:
- `mqcreds`, `oidccreds` and `extcreds`: MQ, OIDC and platform credentials, support external secrets since 2.1.2
- `regcred`: image pull secret, supports external secrets since 2.1.2, can be actively managed since 2.2.5
- `isvdcerts`: new, enables externalization of LDAP key and certificate along with trusted certificates
- `isvdcred`: stores LDAP admin credentials, can now be configured as external secret
- `isvdicerts`: new, enables externalization of ISVDI key and certificate along with trusted certificates
- `isvgimcerts`: new, includes all files under the cert directory, which can now be sourced from vault
- `mqcerts`: new, allows the use of external secrets for MQ key and certficate plus trusted CA certs
- `pgcerts`: new, allows the use of external secrets for Postgres key and certificate
- `pgcreds`: new, enables externalisation of DB and DB Admin credentials

Note:
- configuring `isvdcerts` and `isvdcred` as external secrets only makes sense if `general.install.deployLdap` is enabled
- similarly, enabling an external secret for `isvdicerts` is only effective if ISVDI is deployed by the helm chart (`general.install.deployIsvdi`)
- setting `pgcerts` and `pgcreds` to `true` will not have no effect unless `general.install.deployDb` is alse enabled

The following fixes and improvements are also included:
- `vault-setup.sh`: compatibility with very old version of `grep`, such as GNU 3.6
- `extract-config-response.sh`: fix dbUpgrade for postgres (`generate dbConfigResponse.tablespace.location.*` on upgrade)

## 2.3.2 (2026-02-26)

This version adds enhancements geared towards the ability to deploy multiple environments (such as DEV, TEST or PROD) from a single directory structure rather than having to use separate directories for each environment. Similarly, the divergence between environment specific git branches is also reduced.

Reworked logic for retrieving x509 certificates:
- use optional setting `general.install.certDir` in `values-config.yaml` to override the certificate directory
- default to `config/certs` if explicit setting is absent
- consistently use a named template to create glob pattern for matching files within the certificate directory

The ArgoCD application manifest sample has been updated to demonstrate how git commit hash can be injected by ArgoCD, in the same format `--set revision=$(git log -n 1 --pretty=format:%h)` would do when using `helm` from the command line (which is already documented in README). 

Minor fixes and documentation updates are also included.

## 2.3.1 (2026-02-19)

This version ships templates which deploy product version 11.0.1.1_IF1.

Additionally, minor fixes and documentation updates are included.

## 2.3.0 (2026-02-12)

This version adds chart and version control metadata to the k8s namespace and addresses a compatibility issue with symlinks.

Following annotations are generated for the namespace during template rendering:
- `helm.sh/chart`: chart name and version
- `app.kubernetes.io/version`: version of the product the helm chart deploys
- `version-control/revision`: revision deployed (e.g. git commit hash)

These annotations provide extra visibility into the last deployed desired state.

Further, `config` and `data` symlinking is switched, that is, the real folders are now the ones within the `argo` directory and symlinks pointing to these are created under `starterkit`. The purpose of this change is compability with hardened ArgoCD/Helm where symlinks pointing outside the chart directory are not followed by `.Files.Glob` helm function.

Additionally, minor fixes and documentation updates are included.

## 2.2.5 (2026-01-28)

This version enables deployment of the k8s namespace and the image pull secret.

Prior to this version, the k8s namespace resource and the image pull secret `regcred` had to be created manually, upfront.

Helm templates will now deploy (create and sync) the namespace with all annotations required for pod security admission control.

Image pull secret `regcred` is assumed to be present and externally managed when `general.install.externalSecret.regcred` is set to `true` in `values-config.yaml`, in this case, the templates will not create or alter this resource (also see Vault integration via External Secrets introduced in 2.1.2). Altentively and by default, `regcred` is generated via a special helm template:
- supports multiple repos in the same Secret with separate credentials for each
- input uses the structure of dockerconfigjson, but without the redundant `auth`
- `auth` properties will be dynamically injected for all repo entries
- sample config provided for IBM Container Registry and local repo, see `regcred.yaml`
- abort with an appropriate error message if no repo entry is configured

## 2.2.4 (2026-01-14)

This version ships templates for upstream version 11.0.1.1 and includes documentation updates.

Office 365 Email-based Approval is a new upstream feature which can be configured in `values-config.yaml` via the same options the `configure.sh` script of the original startetkit would create when generating `config.yaml`:
- `monitoring.enabled` (defaults to false)
- `user.id` which defines the UPN or email address to be used
- `tenant.id` to define the directory (tenant) ID of the Azure AD organization
- `client.id` and `client.secret` from the Azure AD app registration
- `scan.interval.minutes` (defaults to 30)

In addition to what the original starterkit supports, the following extra options allow finer control of the Microsoft Graph API:
- `graph.token.endpoint` specifies the token endpoint template where %s will be replaced with tenant ID, the value defaults to https://login.microsoftonline.com/%s/oauth2/v2.0/token
- `graph.messages.endpoint` defines the messages endpoint template where %s will be replaced with user principal name, it defaults to https://graph.microsoft.com/v1.0/users/%s/mailFolders/inbox/messages
- `graph.user.agent` allows to override the User-Agent header for HTTP requests to Microsoft Graph, defaults to "IVIG-EmailApproval/1.0"

## 2.2.3 (2026-01-01)

This version ships several enhancements.

The script `vault-setup.sh` can be used create `secrets.yaml` with random generated passwords and a random 128 bit Data Encryption Key. Generated passwords consist of 16 characters from the base64 alphabet to avoid issues with special characters. Password complexity rules of the middleware components are considered, specifically, the LDAP admin password is randomly generated until it fulfills the following password policies: minLength 8, minAlpha 2, minOther 2, maxRepeated 2. This script is geared towards developers who need to quickly setup a reasonably secure development environment, but may be useful during the initial setup of environments which prefer to manage secrets internally, or where secrets are later moved to an external vault such as HashiCorp Vault.

The utility `extract-config-response.sh` is added to both the main containers of both `isvgimconfig` and `isvgim`. This script can be used either during initial setup of the data tier (once the LDAP and DB is already deployed) or in upgrade scenarios where schema updates and data transformations have to be applied. It recreates silent installer response files for initial data tier setup or upgrade by extracting configuration information from `data/erRole*.properties` files. While the original starterkit requires configuration data - including sensitive data - to be stored in cleartext in `config.yaml` and erased at a specific point of the installation process once the above mentioned property files are generated, our declarative approach ensures the correct property files are available from the beginning, and the input required by `dbConfig.sh` and `ldapConfig.sh` is extracted from these sources.

Minor usability improvements and fixes:
- fix `database.tablespace.location.indexes` in `enRoleDatabase.properties`
- remove trailing whitespace at the end of lines in `data-tpl/*.properties`
- remove trailing whitespace at the end of lines of some other helm templates
- replace tabs by 4 spaces in `data-tpl/*.properties` so configmap can use block string
- reorganize config maps storing extra logic for the init container and utility scripts

## 2.2.2 (2025-12-12)

This version brings the ability to setup x509 certificates.

The `cert-util.sh` script is added to create, renew and list certificates for a configurable set of components. The structure of the certificates is intentionally kept compatible with the original starterkit, but the logic for managing certificates has been externalized, it does not run within the container.

The logic is implemented such that existing cryptographic keys and certificate signing requests are reused when creating or renewing certificates.

Subject alternate names (domain names) are configured according to the requirements of each component, inline with how the original startetkit would create certificates.

This script is intentionally de-couple and self-contained, it does not have dependencies other than `bash` and `openssl`.

Another script, `cert-setup.sh` is included to auto-detects the part of configuration that is relevant for certificates, once `values.yaml` and `values-config.yaml` have already been adjusted. In particular, it will retrieve the k8s namespace from `values.yaml`, collect extra hostnames (which should be added to the certificate of IVIG server) and the list of optional components to be deployed from `values-config.yaml`. This script, after collecting the information required, will invoke `cert-util.sh` to create certificates, and after that, to list the details of the certificates created.

Elliptic Curve prime256v1 keys and certificates are created for the following when `cert-setup.sh` is run:
- `isvgimRootCA`
- `isvgim`
- `mq`
- `isvdi` if `general.install.deployIsvdi` is enabled
- `isvd` if `general.install.deployLdap` is enabled
- `pgsql` if `general.install.deployDb` is enabled

While `cert-setup.sh` is intended to be a convenient "one-click" tool to setup a new environment without specifying any input parameter, it is not as robust and versatile as `cert-util.sh` which comes with a rich set of commandline options that allow finer-grained control of the behavior. Of course, due to project-specific requirements one may have to create and manage certificates via alternative means, in which case these two scripts might serve as reference or inspiration.

## 2.2.1 (2025-11-26)

This version enables optional deployment of DB and LDAP components.

The flags controlling these options and the configuration of the components are intentionally kept compatible with the original starterkit. These components are intended for non-production use.

Deployment of PostgreSQL DB is optional, controlled in `values-config.yaml` via the same flag `general.install.deployDb` the original starterkit uses, and is disabled by default. When enabled, a single server will be deployed to the target namespace and configured for SSL connections.

Improvements to DB setup logic in `db/primary_init_script.sh`:
- fix timestamp bug which reused the timestamp captured at start
- add logic to create data and index directories if these do not exist
- fix userid case sensitivity bug via proper quoting at the right place
- replace tabs with spaces display well when in a configmap

Deployment of LDAP is also optional, disabled by default and enabled via the flag `general.install.deployLdap`, respectively. License information has to be provided in `values-config.yaml` via `general.license.ldapKey` and `general.license.accepted`, just like with the original starterkit, and will be dynamically inserted into `ldap_config.yaml` in the appropriate format. A single instance will be deployed to accept SSL connections from IVIG.

## 2.2.0 (2025-11-14)

This version implements a more secure but at the same time also more convenient approach to protecting sensitive data.

IVIG encrypts sensitive data in property files and also in LDAP via AES, the key used for data encryption is stored in a JCEKS keystore, which is password protected. (Technically, both the keystore and the key entry within it is protected with the same password.) After initial configuration, this password is stored in obfuscated from in the binary file `encryptionKey.properties`. Version 11 introduces another level of encryption - the data encryption key itself is randomly generated during initial configuration and before being stored to the keystore, another randomly generated AES key is used to encrypt the data encryption key. This key encrypting key (KEK) is stored in an obscurely named subdirectory in a file named `masterKey.key`.

The original starterkit requires all these files and directories to be stored under the `data` directory, which would be typically put under version control...

Key benefits of the alternative approach implemented here:
- eliminates the need to store `encryptionKey.properties` which contains the obfuscated keystore password
- does not require KEK (`kek*/masterKey.key`) to be put under version control at all
- does not even store the JCEKS keystore in git
- integrates well with an external vault for securely storing the actual data encryption key (DEK)
- uses a dynamically generated random keystore password (which changes on each restart of the container)
- encrypts DEK with a random KEK which also changes whenever the container is restarted
- securely injects the DEK dynamically into the keystore, in a well isolated manner before the main container starts
- ensures backward compatibility: if a keystore is supplied via a k8s secret, it is used in the traditional way along with the master key and `encryptionKey.properties` stored in the same k8s secret

Further, this version also delivers minor optimizations and enhancements to init containers.

## 2.1.4 (2025-10-20)

This version ships templates for upstream version 11.0.1.0 and includes minor documentation updates.

## 2.1.3 (2025-09-25)

This version moves the credential injection and data folder initialization logic into initcontainers of both the `isvgimconfig` pod and the main application `isvgim`.

Initcontiainers run when the deployment/stateful set is started and terminate once the initialization task is accomplished. The initialized data folder (containing the preconfigured property files with sensitive data encrypted) is copied to an ephemeral (non-persistent) volume shared by the initcontainer and the main container. Once the initcontainer terminates, the main container is started, which takes configuration data from the shared ephemeral volume.

This encapsulation of the initialization logic serves two purposes: ease of maintenance and security hardening. Ease of maintenance is realized through simpler, leaner main containers with reduced amount of references to other K8s resources, and the fact that each container focuses on one particular task. Hardening happens by eliminating the need to expose sensitive data via environment variables within long running containers and thereby decreasing the attack surface (environment variables cannot be deleted within the lifecycle of a given container).

## 2.1.2 (2025-09-16)

This version introduces following features:
- Vault integration via External Secrets (optional) 
- Deployment of ISVDI optional, controlled via the same flag `general.install.deployIsvdi` the original starterkit uses

Interoperability with Vault is achieved via the use of External Secrets. The External Secrets Operator interacts with [HashiCorp Vault](https://www.vaultproject.io/), [IBM Cloud Secrets Manager](https://www.ibm.com/cloud/secrets-manager) or external secret management systems like [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/), [Google Secrets Manager](https://cloud.google.com/secret-manager), [Azure Key Vault](https://azure.microsoft.com/en-us/services/key-vault/), [CyberArk Conjur](https://www.conjur.org/).

The optional Vault integration can be configured via `general.install.externalSecret` selectively for MQ, OIDC and platform credentials, and is disabled by default.

Making the deployment of ISVDI optional demonstrates how the chart's content can be modularized without the additional complexity of using helm subcharts. The flag controlling this option is intentionally kept compatible with the original starterkit.

This version also includes minor cosmetic changes to improve readability/user experience.

## 2.1.1 (2025-09-08)

This version includes reworked logic for generating reduced (post-install) `config.yaml` in `isvgimconfig` configmap.
- deprecates `config/config.yalm` and dynamically created one based on `values-config.yaml`
- support for OICD via `oidc` section in `values-config.yaml`
- support for liberty metrics, encryption flags, truststore and keystore via `server` section in `values-config.yaml`

This version bases on helm templates of upstream version 11.0.0.1_IF1

## 2.1.0 (2025-09-02)

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

The file `config.yaml` needs to exist in its reduced form (post-installation form) for declarative deployment and is preferred not to contain any sensitive data in the form it is stored in Git. Therefore, activation key is dynamically substituted by the templating engine. Any configuration option currently not covered by `values-config.yaml` can be manually added to `config.yaml`.

## 2.0.2 (2025-08-15)

This version attempts to be as close to the original StartetKit as possible, but provide the ability to deploy from Git, with helm only.
- uses the Starterkit as a starting point, maintaining as much compatiblity as possible (a subset of the original folder structure is used)
- all modifications are contained in a folder named `argo`
- include the `config` and `data` folder as-is, via symlinks
- reuse as many existing template as possible, via symlinks under `argo/templates`
- eliminates tarballs hardcoded in helm templates e.g. configmaps isvgimks and isvgimdata
- eliminate the usage of any script which generates helm tempates 'on the fly' such as `createConfigs.sh`
- eliminate the `yaml` folder completely
- the `bin` folder is retained in its original version but is never used

This version bases on helm templates of upstream version 11.0.0.1
