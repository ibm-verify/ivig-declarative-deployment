# Changelog

All notable changes to this project will be documented in this file.

## 2.4.4 (2026-07-16)

This version moves to a more recent External Secrets API version

Templates transition to non-beta External Secrets API, and with this change, all versions from 0.16.2 to 2.7.0 (current) of the External Secrets Operator version are supported when using the optional External Secrets integration.

Further changes:
- updates in README for clarity
- change default configuration in `values-config.yaml` to deploy internal data tier
- add SPDX tags to dynamically generated `*.properties` files

## 2.4.3 (2026-07-09)

This version enhances Vault integration and restructures the repo for packaging.

With this version, the repository structure is updated. The declarative deployment helm chart is moved to its own top level directory `smarterkit` and the few remaining symlinks pointing outside of that folder are dereferenced. This change is carried out to facilitate packaging and distributing declarative deployment as a first-class deployment method for IVIG.

Further improvements:
- gracefully skip patching if no patch exists for given app version
- complete rewrite of Vault helper scripts to minimize dependencies to bash 3.2 and jq 1.5
- documentation updates for Vault integration and in general around secret management

## 2.4.2 (2026-07-02)

This version enables integration with secret management systems such as Vault.

Improved integration is geared towards any secret management platform supported by the External Secrets Operator in general, and covers HashiCorp Vault specifically in depth.

The integration deploys External Secrets for any secret marked as externally managed by setting `general.install.externalSecret.*` to `true`, and is available in two variants:
- Vendor agnostic way, where the ClusterSecretStore is expected to already exist and be configured against one of the secret management platforms supported by the External Secrets Operator
- Vault-based approach where the ClusterSecretStore and service account is automatically deployed

Detailed step-by-step guidance is provided for both variants.

## 2.4.1 (2026-06-18)

This version delivers a patching mechanism and uses it to alter files on startup rather than storing complete files to replace the original counterparts with. The patching mechanism features integrity checking and makes changes only if all files match, no fuzz factor and no heuristics are applied which is a conscious design decision when operating in a containerized environment. Patches are compact and efficiently deal with small changes in many large text files. A patch is specifically built for a certain image version and provides:
- new features/enhancements that extend the capabilities of the original product
- fixes to upstream bugs before product fixpack is publishes (could take months)
- field customizable, project specific tuning such as JVM heap size adjustment

The bundled `11.0.2.0-tweaks.patch` includes changes from all of these 3 categories.

Further, minor improvements in this version:
- propagate license acceptance from `values-config.yaml` to `isvgimconfig/config.yaml` same way it is already done for isvd and isvdi
- change `logs-im` and `logs-liberty` image from busybox to isvgim
- allow specifying the number of replicas for isvdi/dispatcher
- fix several typos in documentation
- document recommendations and guidance for multi-stage setup with Argo CD
- use a new MQ image (security update)
- rename `vault-setup.sh` to `secrets-setup.sh` to avoid confusion with HC Vault

Fixes to new upstream bugs:
- Custom java extensions such as workflow, script or REST, are not loaded
- Broken keystore migration (superseded in this project, but fixing anyway)
- Broken certificate renewal (obsoleted by this project, but fixing anyway)

## 2.4.0 (2026-05-21)

This version bases on upstream version 11.0.2.0 and delivers extra flexibility.

The upstream version adds support for Oracle DB 19c. Declarative deployment increases flexibility and robustness of JDBC configuration beyond what the original product supports. It reads and writes the JDBC URL formats the core product supports with a compatible logic, and additionally offers a new configuration parameter `db.forcedJdbcUrl` in `values-config.yaml` to explicitly set a JDBC connection string rather then providing hostname, port and database name. This allows automated deployment with advanced database configuration (such as load balancing and failover) from scratch, which is not offered by the original product.

New JDBC options one might use with this release:
- Oracle Thin Driver (basic SID style)
- Oracle Thin-Style Service Name (preferred modern syntax)
- Oracle Net Connection Descriptor - Full explicit descriptor
  - with SID or Service Name
  - explicit SSL configuration
  - multiple addresses, RAC, load balancing and failover
  - timeouts and other advances parameters
- DB2 Type4 Driver extra parameters
  - TLS versiona and cipher suite selection
  - high availability (HADR), failover and client reroute (ACR)
  - performance optimisation
  - many more advanced parameters
- Postgres Driver extra parameters
  - multiple hosts, failover and load balancing, read scaling
  - many more advanced parameters

This version proactively supports configuration properties and certificate generation for `isvart`, the Node-based adapter component. The original starterkit currently does not.

Further, minor improvements to the original k8s templates and scripts are cascaded to the enhanced counterparts in this project as well.

With this version, the repository structure is also updated. The `config` and `data` directories are no longer shared between starterkit and declarative deployment. The `config` folder under starterkit, hosts the original content and is not a symlink to `config` under `argo` any longer. Similarly, the `data` symlink is also deleted.

WARNING! Known issues of the original product during upgrade to 11.0.2.0:
1. The LDAP version deployed by the original product was changed and the current upgrade process may result in data loss. Therefore, this project sticks to the previous LDAP version by default to shield the common upgrade scenario from potential data loss. It is advised to manually upgrade the LDAP instance and change LDAP server image versions in `values.yaml` once data has been prepared.
2. `dbUpgrade.sh` is known to abort due to NPE in the ARCUpgrade module and leave the database in an inconsistent state. This potential defect is under investigation by the vendor. It does not impact new deployments but may occur when upgrading from a previous version. Taking a database backup is strongly recommended.

## 2.3.8 (2026-04-30)

This version delivers 3 hardening measures which can be selectively applied.

These measures can be enabled via custom flags not included in the original product. Flags can be activated by setting `server.flags.*` to `true` in `values-config.yaml`. Specifying an unknown flag on a vanilla (non-enhanced) container will yield the error message `./work/parseYaml.sh: line 57: handle_*: command not found` but not cause further errors.

A secure session cookie informs the browser to send the session cookie back only over an HTTPS connection. When this feature is enabled, session cookies over an HTTP connection no longer work. Further, session cookies should instruct the user agent to not expose cookie content to client-side scripts in order to mitigate cross-site scripting (XSS) attacks.

To activate the security measures above, set `server.flags.secureSessionCookies` to `true` in `values-config.yaml`.

HTTP Strict Transport Security (HSTS) is a security policy mechanism that forces web browsers to interact with websites exclusively through secure HTTPS connections. It prevents attackers from downgrading connections to insecure HTTP, protecting against man-in-the-middle attacks and cookie hijacking by ensuring all traffic is encrypted. The server sends a Strict-Transport-Security header to the browser, instructing it to only use HTTPS for a specified time (via max-age).

By default, HSTS header is set for any URL under `/itim`, but endpoints outside of this context (such as `openapi`, `enrole` or `metrics`) are not protected. To globally active this security measure, set `server.flags.globalHSTS` to `true` in `values-config.yaml`.

Server version disclosure enables the attacker to find vulnerabilities easier, potentially leading to targeted attacks with version specific exploits. Therefore, production systems should take measures to avoid sending detailed server version information.

To make the identification of the exact Application Server version harder, set `server.flags.hideServerVersion` to `true` in `values-config.yaml` which yields the following:
- disable Liberty welcome page: the welcome page is enabled by default, so accessing the root context displays the Open Liberty welcome page with version information
- remove server header: these headers are enabled by default, so server version/implementation information is returned to the caller in certain situations
- disable `X-Powered-By` header: in servlet-4.0 and earlier, the `X-Powered-By` header is set by default

## 2.3.7 (2026-04-02)

This version improves ISVDI autodiscovery and liberty metrics configuration.

ISVDI init script autodiscovery is run right after `initAdapterContainer.sh` so `setHostname.sh` would be executed after autodiscovered init scripts are run. This improvement avoids a potential issue where changes made by `setHostname.sh` could be overwritten by autodiscovered scripts on some setups, specifically by an ISVA adapter init script which replaces the original `ibmdisrv` script with an adjusted version, where the original at that point would have already been modified by `setHostname.sh`.

A more secure way is implemented for handing over liberty metrics credentials, which does not require storing sensitive data in git (not even in encrypted form). Both username and password can be left blank (empty or null) in `values-config.yaml` in which case missing data will be read from a k8s secret. This secret by default will be populated based on username in `values-config.yaml` and password specified in `secrets.yaml`, however, the secret can be marked as externally managed in which case it will be assumed to pre-exist (e.g. created and updated by vault, see feature added in 2.1.2).

## 2.3.6 (2026-03-26)

This version delivers improved truststore creation for IVIG and additional flexibility for ISVDI.

During container initialization, certificates are read from PEM files and added to truststores and keystores. Due to a bug in IVIG, only the first entry from a PEM file is processed, causing certificate validation errors when PEM files consisting of multiple entries are used. This version fixes this bug by overriding `parseYaml.sh` in the IVIG container with a tweaked version that properly imports all certificates from PEM files when building the truststores.

ISVDI allows additional configuration scripts to be specified via yaml configuration, but the absence of such scripts causes a crash loop. For the ISVA adapter to function properly, additional initialization logic is needed, which is typically implemented via scripts in the solution directory, on a PVC. The original initialization consists of multiple steps:
1. Start ISVDI without config scripts required by the adapter
2. Use the bundled `adapterUtils` scripts to copy required files to PVC (which requires a running ISVDI container)
3. Amend yaml configuration to reference the custom init script on the PVC
4. Restart the container for the updated init logic to take effect

This creates a chicken and egg problem which does not play well with declarative deployment, as initialization requires a phased approach and deploying the final desired state right away would not yield a correctly functioning environment. This flaw is fixed by adding logic that finds and calls adapter initialization scripts on startup and avoids crash loops caused by missing scripts.

Additionally, a reasonable default value is used for nonexistent or empty `encryptionKey.properties` with the intention to avoid false positives during comparison of the desired state with the actual state (cosmetic improvement for ArgoCD diff).

## 2.3.5 (2026-03-19)

This version improves flexibility of certificate creation and introduces minor improvements

The script `cert-util.sh` is enhanced to allow subjectAltName override for all auto-deployed components:
- IVIG itself via `ISVGIM_ALTNAME`
- MQ via `MQ_ALTNAME`
- Directory Server via `ISVD_ALTNAME`
- Directory Integrator via `ISVDI_ALTNAME`
- Postgres DB via `PGSQL_ALTNAME`

Note: Before this version, specifying subjectAltNames via environment variables was available for any additional component, but not for auto-deployed core components.

Further, a more compact, optimized mechanism is used to include certificates in ConfigMaps or Secrets, this change yields more intuitive, easier to read templates.

Cosmetic changes:
- trailing whitespace removal on the few files taken over from the original starterkit
- clearly indicate that the chart is not limited to deployments with external data tier

## 2.3.4 (2026-03-12)

This version delivers compatibility improvements of non-essential convenience scripts which can be run locally to quickly bootstrap an environment. Although GNU/Linux is the primary target platform, MacOS support has been requested. The current version of MacOS still ships with an extremely outdated bash version (3.2.57 from 2007) due to GPLv3 licensing issues. Convenience scripts are compatible with this old bash version as well as BSD sed and grep.
- make `cert-util.sh` work with bash-3.2
- make `cert-setup.sh` work with BSD sed
- update documentation of dependencies and compatibility

Further, a bug inherited from the original starterkit is corrected. Platform credentials (specifically LDAP, DB, DBADMIN, APPSERVER, ISIMSYSTEM and MAIL) consisting of 48 or more characters would yield errors. This issue is addressed in this project.

Minor documentation updates are also included, along with a section documenting advanced use of `cert-util.sh`.

## 2.3.3 (2026-03-05)

This version changes the approach how x509 certificates are passed to containers.

Cryptographic keys clearly qualify as sensitive data. Certificates, Certificate Signing Requests and similar files are inherently environment specific, while application configuration is predominantly stage agnostic within the same project. Although certificates (public keys) could be stored within git without a security concern, it may be more manageable to handle private keys and certificates together, via Vault or a similar secret store. The same vehicle that can store private keys outside of git and inject these at runtime can also be used to store and inject certificates.

The following concept is implemented for all files related to x509 certificates:
- remove all certificates, key, CSRs etc. from configmaps
- store certificates and related files to dedicated k8s secrets (opaque cert-secrets)
- define projected volumes to merge the contents of cert-secrets and configmaps
- mount projected volumes to existing directories to maintain compatibility
- apply conditional template rendering to selectively enable external secrets for such cert-secrets

This clean separation enables vault integration for the following secrets which can be individually toggled via `general.install.externalSecret.*`:
- `mqcreds`, `oidccreds` and `extcreds`: MQ, OIDC and platform credentials, support external secrets since 2.1.2
- `regcred`: image pull secret, supports external secrets since 2.1.2, can be actively managed since 2.2.5
- `isvdcerts`: new, enables externalization of LDAP key and certificate along with trusted certificates
- `isvdcred`: stores LDAP admin credentials, can now be configured as external secret
- `isvdicerts`: new, enables externalization of ISVDI key and certificate along with trusted certificates
- `isvgimcerts`: new, includes all files under the cert directory, which can now be sourced from vault
- `mqcerts`: new, allows the use of external secrets for MQ key and certificate plus trusted CA certs
- `pgcerts`: new, allows the use of external secrets for Postgres key and certificate
- `pgcreds`: new, enables externalisation of DB and DB Admin credentials

Note:
- configuring `isvdcerts` and `isvdcred` as external secrets only makes sense if `general.install.deployLdap` is enabled
- similarly, enabling an external secret for `isvdicerts` is only effective if ISVDI is deployed by the helm chart (`general.install.deployIsvdi`)
- setting `pgcerts` and `pgcreds` to `true` will not have no effect unless `general.install.deployDb` is also enabled

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

Further, `config` and `data` symlinking is switched, that is, the real folders are now the ones within the `argo` directory and symlinks pointing to these are created under `starterkit`. The purpose of this change is compatibility with hardened ArgoCD/Helm where symlinks pointing outside the chart directory are not followed by `.Files.Glob` helm function.

Additionally, minor fixes and documentation updates are included.

## 2.2.5 (2026-01-28)

This version enables deployment of the k8s namespace and the image pull secret.

Prior to this version, the k8s namespace resource and the image pull secret `regcred` had to be created manually, upfront.

Helm templates will now deploy (create and sync) the namespace with all annotations required for pod security admission control.

Image pull secret `regcred` is assumed to be present and externally managed when `general.install.externalSecret.regcred` is set to `true` in `values-config.yaml`, in this case, the templates will not create or alter this resource (also see Vault integration via External Secrets introduced in 2.1.2). Alternatively and by default, `regcred` is generated via a special helm template:
- supports multiple repos in the same Secret with separate credentials for each
- input uses the structure of dockerconfigjson, but without the redundant `auth`
- `auth` properties will be dynamically injected for all repo entries
- sample config provided for IBM Container Registry and local repo, see `regcred.yaml`
- abort with an appropriate error message if no repo entry is configured

## 2.2.4 (2026-01-14)

This version ships templates for upstream version 11.0.1.1 and includes documentation updates.

Office 365 Email-based Approval is a new upstream feature which can be configured in `values-config.yaml` via the same options the `configure.sh` script of the original starterkit would create when generating `config.yaml`:
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

Subject alternate names (domain names) are configured according to the requirements of each component, inline with how the original starterkit would create certificates.

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

Initcontainers run when the deployment/stateful set is started and terminate once the initialization task is accomplished. The initialized data folder (containing the preconfigured property files with sensitive data encrypted) is copied to an ephemeral (non-persistent) volume shared by the initcontainer and the main container. Once the initcontainer terminates, the main container is started, which takes configuration data from the shared ephemeral volume.

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
- uses the Starterkit as a starting point, maintaining as much compatibility as possible (a subset of the original folder structure is used)
- all modifications are contained in a folder named `argo`
- include the `config` and `data` folder as-is, via symlinks
- reuse as many existing template as possible, via symlinks under `argo/templates`
- eliminates tarballs hardcoded in helm templates e.g. configmaps isvgimks and isvgimdata
- eliminate the usage of any script which generates helm templates 'on the fly' such as `createConfigs.sh`
- eliminate the `yaml` folder completely
- the `bin` folder is retained in its original version but is never used

This version bases on helm templates of upstream version 11.0.0.1
