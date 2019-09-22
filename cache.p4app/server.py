#!/usr/bin/env python

import sys
import socket
from cache_protocol import *

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('', UDP_PORT))

store = {1: 11, 2: 22}

# Load some key/values from args, e.g. ./server.py 1=11 3=123
for arg in sys.argv[1:]:
    k,v = map(int, arg.split('='))
    store[k] = v

while True:
    req, addr = s.recvfrom(1024)
    key, = reqHdr.unpack(req)

    print addr, "-> Req(%d),"%key,

    if key in store:
        valid, value = 1, store[key]
        print "<- Res(%d)" % value
    else:
        valid, value = 0, 0
        print "<- Res(NOTFOUND)"


    res = resHdr.pack(key, valid, value)
    s.sendto(res, addr)

