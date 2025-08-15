#!/usr/bin/bash
CACERTS=/opt/ibm/java/jre/lib/security/cacerts
CERTDIR=/tmp/isvgimcfg

certflag=0
certnum=0
while IFS= read -r line; do
  if [ $certflag -eq 1 ]; then
    # Handle both types of quotes
    echo $line | grep -q "'"
    if [ $? -eq 0 ]; then
      cert=$(echo $line | cut -d "'" -f 2)
    else
      cert=$(echo $line | cut -d '"' -f 2)
    fi
    if [[ $cert == @* ]]; then
      cert=$(echo $cert | cut -d '@' -f 2)
      cp $CERTDIR/$cert /tmp/cacert.$certnum
      certnum=$(($certnum+1))
    fi
    if [[ $cert == B64:* ]]; then
      cert=$(echo $line | cut -d ':' -f 2-)
      echo -n "$cert" | base64 -d > /tmp/cacert.$certnum
      certnum=$(($certnum+1))
    fi
  fi
  if [[ $line =~ ^.+truststore:.* ]]; then
    certflag=1
  fi
  if [[ $line =~ ^.+keystore:.* ]]; then
    certflag=0
  fi
done < $CERTDIR/config.yaml
for CA in `ls /tmp/cacert.*`; do
  ALIAS=$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16 ; echo '')
  keytool -importcert -noprompt -keystore $CACERTS -storepass "changeit" -storetype jks -file $CA -alias $ALIAS | grep -v IBMJCEPlusFIPS
done
