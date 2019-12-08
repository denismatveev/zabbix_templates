#!/usr/bin/env python
# -*-coding:utf-8 -*

import itertools
import re
import sys
import glob
# consider left is remote side, right is local
conf_files = '/etc/ipsec.d/*.conf'

def parseConf(ipsec_conf):
    reg_conn = re.compile('^conn\s([-\w]+)')
    reg_left = re.compile('left=(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
    reg_right = re.compile('right=(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
    reg_left_net = re.compile('[^#]leftsubnets{0,1}=([\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}]+)')
    data = []
    with open(ipsec_conf, 'r') as f:
        for key, group in itertools.groupby(f, lambda line: line.startswith('\s')):
            if not key:
                conn_info = list(group)
                conn_tmp = [m.group(1) for l in conn_info for m in [reg_conn.search(l)] if m]
                net_tmp = [m.group(1) for l in conn_info for m in [reg_left_net.search(l)] if m]
                net_tmp_list = net_tmp[0].split(",")
                if conn_tmp and net_tmp:
                    for net in net_tmp_list:
                      conn_net = [conn_tmp[0],net]
                      data.append(conn_net)
        return data
def getTemplate():
    template = """
        {{ "{{#TUNNEL}}": "{0}",
          "{{#REMOTE_NETWORK}}": "{1}" 
        }}"""

    return template

def getPayload():
    final_conf = """{{
    "data":[{0}
    ]
}}"""
    conf = ''
    for filename in glob.glob(conf_files):
      data = parseConf(filename);
      for tunnel in data:
            tmp_conf = getTemplate().format(
                tunnel[0],
                tunnel[1]
            )
            conf += '%s,' % (tmp_conf)

    if conf[-1] == ',':
        conf=conf[:-1]

    return final_conf.format(conf)


if __name__ == "__main__":

    ret = getPayload()
    sys.exit(ret)
