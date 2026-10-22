#!/bin/bash
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: MIT

sed -i -e '1113r /dev/stdin' -e '1113,1114d' /opt/IBM/TDI/jvm/jre/conf/security/java.security << 'EOF'
jdk.tls.disabledAlgorithms=3DES_EDE_CBC, DES, DH keySize < 2048, DTLSv1.0, \
    EC keySize < 224, ECDH, MD5withRSA, NULL, RC4, SSLv3, TLSv1, TLSv1.1, anon, \
    TLS_CHACHA20_POLY1305_SHA256, \
    TLS_DHE_DSS_WITH_AES_128_CBC_SHA, \
    TLS_DHE_DSS_WITH_AES_128_CBC_SHA256, \
    TLS_DHE_DSS_WITH_AES_128_GCM_SHA256, \
    TLS_DHE_DSS_WITH_AES_256_CBC_SHA, \
    TLS_DHE_DSS_WITH_AES_256_CBC_SHA256, \
    TLS_DHE_DSS_WITH_AES_256_GCM_SHA384, \
    TLS_DHE_RSA_WITH_AES_128_CBC_SHA, \
    TLS_DHE_RSA_WITH_AES_128_CBC_SHA256, \
    TLS_DHE_RSA_WITH_AES_128_GCM_SHA256, \
    TLS_DHE_RSA_WITH_AES_256_CBC_SHA, \
    TLS_DHE_RSA_WITH_AES_256_CBC_SHA256, \
    TLS_DHE_RSA_WITH_AES_256_GCM_SHA384, \
    TLS_DHE_RSA_WITH_CHACHA20_POLY1305_SHA256, \
    TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA, \
    TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA, \
    TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256, \
    TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA, \
    TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA, \
    TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256, \
    TLS_EMPTY_RENEGOTIATION_INFO_SCSV, \
    TLS_RSA_WITH_AES_128_CBC_SHA, \
    TLS_RSA_WITH_AES_128_CBC_SHA256, \
    TLS_RSA_WITH_AES_128_GCM_SHA256, \
    TLS_RSA_WITH_AES_256_CBC_SHA, \
    TLS_RSA_WITH_AES_256_CBC_SHA256, \
    TLS_RSA_WITH_AES_256_GCM_SHA384, \
    X25519, X448
EOF

sed -i -e '527r /dev/stdin' -e '527d' /opt/IBM/TDI/jvm/jre/conf/security/java.security << 'EOF'
securerandom.strongAlgorithms=SHA512DRBG:OpenJCEPlusFIPS
EOF

sed -i -e '174r /dev/stdin' -e '174,177d' /opt/IBM/TDI/jvm/jre/conf/security/java.security << 'EOF'
RestrictedSecurity.OpenJCEPlusFIPS.FIPS140-3.desc.hash = SHA256:f905b6c69c3538c87ca915aacc502de55a6b711ed799da89afe872f87d4a9b3b
RestrictedSecurity.OpenJCEPlusFIPS.FIPS140-3.desc.number = Certificate #4755
RestrictedSecurity.OpenJCEPlusFIPS.FIPS140-3.desc.policy = https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4755
RestrictedSecurity.OpenJCEPlusFIPS.FIPS140-3.desc.sunsetDate = 2029-08-08
EOF

sed -i -e '66r /dev/stdin' -e '66,77d' /opt/IBM/TDI/jvm/jre/conf/security/java.security << 'EOF'
security.provider.1=com.ibm.crypto.plus.provider.OpenJCEPlusFIPS
security.provider.2=SUN
security.provider.3=SunRsaSign
security.provider.4=SunEC
security.provider.5=SunJSSE
security.provider.6=SunJCE
security.provider.7=SunJGSS
security.provider.8=SunSASL
security.provider.9=XMLDSig
security.provider.10=SunPCSC
security.provider.11=JdkLDAP
security.provider.12=JdkSASL
security.provider.13=SunPKCS11
EOF
