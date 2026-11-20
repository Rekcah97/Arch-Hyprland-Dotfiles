#!/bin/bash
# The kernel already toggles rfkill on this key; just wait a moment and report the state.
sleep 0.3

if rfkill list | grep -q "Soft blocked: no"; then
    swayosd-client --custom-icon airplane-mode-disabled-symbolic --custom-message "Airplane mode off"
else
    swayosd-client --custom-icon airplane-mode-symbolic --custom-message "Airplane mode on"
fi