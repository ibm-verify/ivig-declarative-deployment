#!/bin/bash

HOST=$(echo $POD_IP | cut -d '=' -f 2 | tr '.' '-')
sed -i "s/\(MIXEDMODE_FLAG\)/\1 -Djava.rmi.server.hostname=${HOST}.{{ .Values.namespace }}.pod.cluster.local/" /opt/IBM/TDI/ibmdisrv
sed -i "s/\(objectPort=\).*/\1{{ .Values.services.isvdi.ports.object }}/" /home/isvdi/solution.properties
