#!/bin/bash
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: MIT

# Override RMI Dispatcher properties in Verify Directory Integrator container 
#
# This script is intented to be placed under smarterkit/config/adapters where it
# will be automatically discovered any executed before Directory Integrator
# starts.

# Replace the default value of an existing key in itim_listener.properties file.
# Safe for alphanumeric keys and values, full BRE input sanitization not needed.
set_prop() {
    sed -i "s/^$1=.*$/$1=$2/" "/opt/IBM/TDI/itim_listener.properties"
}

# Uncomment individual lines and adjust values to override the default setting.

#set_prop ALShutdownTimeout            300

#set_prop SearchResultSetSize          100
#set_prop SearchALUnusedTimeout        600
#set_prop SearchReaperThreadTimeOut    300

#set_prop ALCacheSize                  100
#set_prop AssemblylineCacheTimeout     600
set_prop  GlobalRunALCount             200
#set_prop MaxWaitingALcount            0

#set_prop ExecuteTestALTimeOut         0
#set_prop ExecuteSearchALTimeOut       0
#set_prop ExecuteAddALTimeOut          0
#set_prop ExecuteModifyALTimeOut       0
#set_prop ExecuteDeleteALTimeOut       0

#set_prop SleepAfterInterrupt          20
#set_prop FailTimeoutRequest           0
