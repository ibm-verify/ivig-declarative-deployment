#!/bin/bash
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: MIT

patch /opt/IBM/TDI/jvm/jre/conf/security/java.security <<EOF
66,77c66,78
< security.provider.1=SUN
< security.provider.2=SunRsaSign
< security.provider.3=SunEC
< security.provider.4=SunJSSE
< security.provider.5=SunJCE
< security.provider.6=SunJGSS
< security.provider.7=SunSASL
< security.provider.8=XMLDSig
< security.provider.9=SunPCSC
< security.provider.10=JdkLDAP
< security.provider.11=JdkSASL
< security.provider.12=SunPKCS11
---
> security.provider.1=com.ibm.crypto.plus.provider.OpenJCEPlusFIPS
> security.provider.2=SUN
> security.provider.3=SunRsaSign
> security.provider.4=SunEC
> security.provider.5=SunJSSE
> security.provider.6=SunJCE
> security.provider.7=SunJGSS
> security.provider.8=SunSASL
> security.provider.9=XMLDSig
> security.provider.10=SunPCSC
> security.provider.11=JdkLDAP
> security.provider.12=JdkSASL
> security.provider.13=SunPKCS11
527c528
< securerandom.strongAlgorithms=NativePRNGBlocking:SUN,DRBG:SUN
---
> securerandom.strongAlgorithms=SHA512DRBG:OpenJCEPlusFIPS
1113c1114,1143
< jdk.tls.disabledAlgorithms=3DES_EDE_CBC, DES, DH keySize < 1024, DTLSv1.0, EC keySize < 224, ECDH, MD5withRSA, NULL, RC4, SSLv3, TLSv1, TLSv1.1, anon
---
> jdk.tls.disabledAlgorithms=3DES_EDE_CBC, DES, DH keySize < 2048, DTLSv1.0, \
>     EC keySize < 224, ECDH, MD5withRSA, NULL, RC4, SSLv3, TLSv1, TLSv1.1, anon, \
>     TLS_CHACHA20_POLY1305_SHA256, \
>     TLS_DHE_DSS_WITH_AES_128_CBC_SHA, \
>     TLS_DHE_DSS_WITH_AES_128_CBC_SHA256, \
>     TLS_DHE_DSS_WITH_AES_128_GCM_SHA256, \
>     TLS_DHE_DSS_WITH_AES_256_CBC_SHA, \
>     TLS_DHE_DSS_WITH_AES_256_CBC_SHA256, \
>     TLS_DHE_DSS_WITH_AES_256_GCM_SHA384, \
>     TLS_DHE_RSA_WITH_AES_128_CBC_SHA, \
>     TLS_DHE_RSA_WITH_AES_128_CBC_SHA256, \
>     TLS_DHE_RSA_WITH_AES_128_GCM_SHA256, \
>     TLS_DHE_RSA_WITH_AES_256_CBC_SHA, \
>     TLS_DHE_RSA_WITH_AES_256_CBC_SHA256, \
>     TLS_DHE_RSA_WITH_AES_256_GCM_SHA384, \
>     TLS_DHE_RSA_WITH_CHACHA20_POLY1305_SHA256, \
>     TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA, \
>     TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA, \
>     TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256, \
>     TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA, \
>     TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA, \
>     TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256, \
>     TLS_EMPTY_RENEGOTIATION_INFO_SCSV, \
>     TLS_RSA_WITH_AES_128_CBC_SHA, \
>     TLS_RSA_WITH_AES_128_CBC_SHA256, \
>     TLS_RSA_WITH_AES_128_GCM_SHA256, \
>     TLS_RSA_WITH_AES_256_CBC_SHA, \
>     TLS_RSA_WITH_AES_256_CBC_SHA256, \
>     TLS_RSA_WITH_AES_256_GCM_SHA384, \
>     X25519, X448
EOF
