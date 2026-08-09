#!/bin/bash

while true; do
  clear
  free -h
  sudo sh -c "echo 2 >  /proc/sys/vm/drop_caches"
  sleep 1
done
