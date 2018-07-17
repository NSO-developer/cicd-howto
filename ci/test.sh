#!/bin/bash
ncs || exit 1
echo "show packages" | ncs_cli -u admin
exit $?
