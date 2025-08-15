#!/bin/bash

HOST=$(basename $YAML_CONFIG_FILE | sed 's/_config.yaml//')
sed -i "s/\(MIXEDMODE_FLAG\)/\1 -Djava.rmi.server.hostname=${HOST}/" /opt/IBM/TDI/ibmdisrv
sed -i "s/\(objectPort=\).*/\1{{ .Values.services.isvdi.ports.object }}/" /home/isvdi/solution.properties
