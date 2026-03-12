#!/bin/bash

usage() {
  cat <<EOM
Create, renew or show certificates used by IVIG deployment
usage: $0 [OPTION...]

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
EOM
  exit 1
}

abort() {
  echo "ABORTING: $1"
  exit 1
}

cert_cnf () {
cat <<EOM
[ req ]
distinguished_name  = subject
string_mask         = utf8only

[ subject ]

[ ca_ext ]
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true
keyUsage               = critical, digitalSignature, cRLSign, keyCertSign

[ server_cert ]
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
EOM
}

CERT_DIR=$(dirname "${BASH_SOURCE[0]}" )/config/certs
NAMESPACE="isvgim"
FQDN="idm.demo.com"
INCLUDE="isvd,isvdi,pgsql"

if [[ $# -lt 1 ]]; then
 usage
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--create) OP=create; shift;;
    -r|--renew) OP=renew; shift;;
    -l|--list) OP=list; shift;;
    -n|--namespace) shift; NAMESPACE=$1; shift;;
    -d|--directory) shift; CERT_DIR=$1; shift;;
    -f|--fqdn) shift; FQDN=$1; shift;;
    -i|--include) shift; INCLUDE=$1; shift;;
    *) usage;;
  esac
done

ISVGIM_ALTNAME="DNS:${FQDN//,/, DNS:}, DNS:isvgim"
MQ_ALTNAME="DNS:mqshare, DNS:mq-headless, DNS:localhost"
ISVDI_ALTNAME="DNS:isvdi, DNS:*.${NAMESPACE}.pod.cluster.local"
ISVD_ALTNAME="DNS:isvd-replica-1"
PGSQL_ALTNAME="DNS:postgres"

issue_cert() {
  openssl x509 -req -in ${1}.csr -out ${1}.crt -extfile <(cert_cnf) -extensions server_cert -copy_extensions copy -CA isvgimRootCA.crt -CAkey isvgimRootCA.key -CAserial isvgimRootCA.srl -CAcreateserial -days 1825 -sha256
  [[ $1 =~ ^isvdi?$ ]] && cat ${1}.key ${1}.crt > ${1}.pem
}

req_cert() {
  ALTNAME=$(tr a-z A-Z <<< $1)_ALTNAME # bash-3.2 compatible alternative to ALTNAME=${1@U}_ALTNAME
  openssl req -config <(cert_cnf) -addext "subjectAltName = ${!ALTNAME}" -new -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -keyout ${1}.key -out ${1}.csr -subj "/CN=${T}/O=isvgim/DC=isvgim"
}

mkdir -p $CERT_DIR && cd $CERT_DIR || abort "cannot change to $CERT_DIR"

case $OP in
  create)
    # setup CA if it does not exist
    [ -f isvgimRootCA.key ] || openssl ecparam -genkey -name prime256v1 -out isvgimRootCA.key
    [ -f isvgimRootCA.crt ] || openssl req -config <(cert_cnf) -extensions ca_ext -x509 -new -nodes -key isvgimRootCA.key -sha256 -days 3650 -out isvgimRootCA.crt -subj "/CN=rootCA/O=isvgim/DC=isvgim"
    for T in isvgim mq ${INCLUDE//,/ }; do
      [ -f ${T}.csr ] || req_cert $T || abort "failed to create certificate request for $T"
      issue_cert $T
    done
    ;;
  renew)
    for CSR in $(ls *.csr); do
      issue_cert ${CSR%.*}
    done
    ;;
  list)
    echo "Listing subjectAltName and expiration date of certificates:"
    for CERT in $(ls *.crt); do
      echo -e "\n[${CERT}]" && cat $CERT | openssl x509 -noout -ext subjectAltName -enddate
    done
    ;;
  *)
    echo "noop";;
esac

