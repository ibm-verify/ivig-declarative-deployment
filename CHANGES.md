# Changelog

All notable changes to this project will be documented in this file.

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

This version also included minor cosmetic changes to improve readability/user experience.

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

The file `config.yaml` a needs to exist in its reduced form (post-installation form) for declarative deployment and is preferred not to contain any sensitive data in the form it is stored in Git. Therefore, activation key is dynamically substituted by the templating engine. Any configuration option currently not covered by `values-config.yaml` can be manually added to `config.yaml`.

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
