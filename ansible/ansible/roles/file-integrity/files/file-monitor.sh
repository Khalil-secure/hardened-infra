#!/bin/bash
inotifywait -m -e modify,attrib,move,create,delete \
  /etc/passwd \
  /etc/shadow \
  /etc/ssh/sshd_config \
  >> /var/log/file-monitor.log 2>&1
