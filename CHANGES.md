# Changelog

All notable changes to this project will be documented in this file.

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

The file `config.yaml` a needs to exist in it's reduced form (post-installation form) for declarative deployment and preferred to not contain any sensitive data in the form it is stored in Git. Therefore, activation key is dynamically substituted by the templating engine. Any configuration option currently not covered by `values-config.yaml` can be manually added to `config.yaml`.

## 2.0.2 (2025-08-15)

This version attempt to be as close to the original StartetKit as possible, but provide the ability to deploy from Git, with helm only.
- uses the Starterkit as a starting point, maintaining as much compatiblity as possible (a subset of the original folder structure is used)
- all modifications are contained a folder named `argo`
- include the `config` and `data` folder as-is, via symlinks
- reuse as many existing template as possible, via symlinks under `argo/templates`
- eliminates tarballs hardcoded in helm templates e.g. configmaps isvgimks and isvgimdata
- eliminate the usage of any script which generates helm tempates 'on the fly' such as `createConfigs.sh`
- eliminate the `yaml` folder completely
- the `bin` folder is retained in it's original version but is never used

This version bases on helm templates of upstream version 11.0.0.1
