# Extras not included in the original product

## Enhanced approach to securing sensitive data

Sensitive data such as passwords or encryption keys should not be hardcoded in source code or built into container images. While storing clear text sensitive date is strictly prohibited, it is even discouraged to stored sensitive data in Git or other source control repositories in encrypted form. Further, passing sensitive data to containers via k8s configmaps is also deemed inappropriate.

### Proper separation of sensitive and non-sensitive data

Proper separation of sensitive and non-sensitive data is a security measure in itself and a prerequisite to enabling additional layers of data protection. All sensitive data is encapsulated in k8s Secrets.

### Dynamic credential injection

This enhancement moves the credential injection and data folder initialization logic into initcontainers of both the `isvgimconfig` pod and the main application `isvgim`.

Initcontiainers run when the deployment/stateful set is started and terminate once the initialization task is accomplished. The initialized data folder (containing the preconfigured property files with sensitive data encrypted) is copied to an ephemeral (non-persistent) volume shared by the initcontainer and the main container. Once the initcontainer terminates, the main container is started, which takes configuration data from the shared ephemeral volume.

This encapsulation of the initialization logic serves two purposes: ease of maintenance and security hardening. Ease of maintenance is realized through simpler, leaner main containers with reduced amount of references to other K8s resources, and the fact that each container focuses on one particular task. Hardening happens by eliminating the need to expose sensitive data via environment variables within long running containers and thereby decreasing the attack surface (environment variables cannot be deleted within the lifecycle of a given container).

### Improved protection of data encyption keys

This enhancement implements a more secure but at the same time also more convenient approach to protecting sensitive data.

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

### Interoperability with external secret management systems such as HashiCorp Vault

Interoperability with Vault or other secret management systems is achieved via the use of External Secrets. The External Secrets Operator interacts with [HashiCorp Vault](https://www.vaultproject.io/), [IBM Cloud Secrets Manager](https://www.ibm.com/cloud/secrets-manager) or external secret management systems like [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/), [Google Secrets Manager](https://cloud.google.com/secret-manager), [Azure Key Vault](https://azure.microsoft.com/en-us/services/key-vault/), [CyberArk Conjur](https://www.conjur.org/).

The optional Vault integration can be configured via `general.install.externalSecret` selectively for various credentials, image pull secret and x509 keys and certificates, and is disabled by default.

The following secrets can be individually toggled via `general.install.externalSecret.*`:
- `mqcreds`, `oidccreds` and `extcreds`: MQ, OIDC and platform credentials, support external secrets since 2.1.2
- `regcred`: image pull secret, supports external secrets since 2.1.2, can be actively managed since 2.2.5
- `isvdcerts`: since 2.3.3, enables externalization of LDAP key and certificate along with trusted certificates
- `isvdcred`: stores LDAP admin credentials, can be configured as external secret since 2.3.3
- `isvdicerts`: as of version 2.3.3, enables externalization of ISVDI key and certificate along with trusted certificates
- `isvgimcerts`: includes all files under the cert directory, which can be sourced from vault since 2.3.3
- `mqcerts`: since 2.3.3, allows the use of external secrets for MQ key and certficate plus trusted CA certs
- `pgcerts`: allows the use of external secrets for Postgres key and certificate, available since 2.3.3
- `pgcreds`: enables externalisation of DB and DB Admin credentials since 2.3.3
- `metricscreds`: enables liberty metrics credentials to be provided externally since 2.3.7

Note:
- configuring `isvdcerts` and `isvdcred` as external secrets only makes sense if `general.install.deployLdap` is enabled
- similarly, enabling an external secret for `isvdicerts` is only effective if ISVDI is deployed by the helm chart (`general.install.deployIsvdi`)
- setting `pgcerts` and `pgcreds` to `true` will not have no effect unless `general.install.deployDb` is alse enabled

## Enhancements for General Hardening

Various security measures can be enabled via custom flags not included in the original product. Flags can be activated by setting `server.flags.*` to `true` in `values-config.yaml`.

Specifying an unkown flag on a vanilla (non-enhanced) container will yield the error message `./work/parseYaml.sh: line 57: handle_*: command not found` but not cause further errors.

### Secure session cookies

A secure session cookie informs the browser to send the session cookie back only over an HTTPS connection. When this feature is enabled, session cookies over an HTTP connection no longer work. Further, session cookies should instruct the user agent to not expose cookie content to client-side scripts in order to mitigate cross-site scripting (XSS) attacks.

To activate the security measures above, set `server.flags.secureSessionCookies` to `true` in `values-config.yaml`.

When this flag is set, Liberty Application Server configuration is amended during initialization with the following `httpSession` properties:
- `cookieHttpOnly`: Specifies that session cookies include the HttpOnly field. Browsers that support the HttpOnly field do not enable cookies to be accessed by client-side scripts. Using the HttpOnly field will help prevent cross-site scripting attacks.
- `cookieSecure`: Specifies that the session cookies include the secure field.

Note that this flag is not available in the original product.

### HTTP Strict Transport Security (HSTS)

HTTP Strict Transport Security (HSTS) is a security policy mechanism that forces web browsers to interact with websites exclusively through secure HTTPS connections. It prevents attackers from downgrading connections to insecure HTTP, protecting against man-in-the-middle attacks and cookie hijacking by ensuring all traffic is encrypted. The server sends a Strict-Transport-Security header to the browser, instructing it to only use HTTPS for a specified time (via max-age).

By default, HSTS header is set for any URL under `/itim`, but endpoints outside of this context (such as `openapi`, `enrole` or `metrics`) are not protected. To globally active this security measure, set `server.flags.globalHSTS` to `true` in `values-config.yaml`.

When this flag is set, Liberty Application Server configuration is amended during initialization with `webContainer` property `addStrictTransportSecurityHeader` to globally enable the HTTP Strict Transport Security (HSTS) header for HTTPS responses and set value  `"max-age=31536000;includeSubDomains"` for that header.

Note that this flag is not available in the original product.

### Hide server version

Server version disclosure enables the attacker to find vulnerabilities easier, potentially leading to targeted attacks with version specific exploits. Therefore, production systems should take measures to avoid sending detailed server version information.

To make the identification of the exact Application Server version harder, set `server.flags.hideServerVersion` to `true` in `values-config.yaml` which yields the following:
- disable Liberty welcome page: the welcome page is enabled by default, so accessing the root context displays the Open Liberty welcome page with version information
- remove server header: these headers are enabled by default, so server version/implementation information is returned to the caller in certain situations
- disable `X-Powered-By` header: in servlet-4.0 and earlier, the `X-Powered-By` header is set by default

Note that this flag is not available in the original product.

## Bugfixes

Some bugs identified in the original product carry high impact and therefore are fixed locally in this project. Once a future version of the original product delivers fixes for these bugs, these local fixes will be retired.

### Correctly import all certificates from PEM files

During container initialization, certficates are read from PEM files and added to truststores and keystores. Due to a bug in IVIG, only the first entry from a PEM file is processed, causing certificate validation errors when PEM files consisting of multiple entries are used. This project fixes the bug by overriding `parseYaml.sh` in the IVIG container with a tweaked version that properly imports all certificates from PEM files when builing the truststores.

### Correctly handle long passwords

A bug inherited from the original product is corrected. Platform credentials (specifically LDAP, DB, DBADMIN, APPSERVER, ISIMSYSTEM and MAIL) consisting of 48 or more characters would yield errors. This issue is addressed in this project and the fix is expected to be delivered with a future version of the original product as well.

