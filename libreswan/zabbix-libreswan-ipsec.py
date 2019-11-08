#!/usr/bin/env python
# -*-coding:utf-8 -*

import itertools
import re
import sys
import glob
import json
# consider left is remote side, right is local
conf_files = '/etc/ipsec.d/*.conf'

def parseConf(ipsec_conf):
    reg_conn = re.compile('^conn\s([-\w]+)')
    reg_left = re.compile('left=(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
    reg_right = re.compile('right=(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
    reg_left_net = re.compile('[^#]leftsubnets{0,1}=([\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}]+)')
    data = {}
    with open(ipsec_conf, 'r') as f:
        for key, group in itertools.groupby(f, lambda line: line.startswith('\s')):
            if not key:
                conn_info = list(group)
                conn_tmp = [m.group(1) for l in conn_info for m in [reg_conn.search(l)] if m]
                left_tmp = [m.group(1) for l in conn_info for m in [reg_left.search(l)] if m]
                right_tmp = [m.group(1) for l in conn_info for m in [reg_right.search(l)] if m]
                left_net_tmp = [m.group(1) for l in conn_info for m in [reg_left_net.search(l)] if m]
                if conn_tmp and left_tmp and right_tmp and left_net_tmp:
                    data[conn_tmp[0]] = [left_tmp[0], right_tmp[0], json.dumps((left_net_tmp[0].strip()).split(","))]
        return data
def getTemplate():
    template = """
        {{ "{{#TUNNEL}}": "{0}",
          "{{#TARGETIP}}": "{1}",
          "{{#SOURCEIP}}": "{2}", 
          "{{#REMOTENETWORKS}}": {3} 
        }}"""

    return template

def getPayload():
    final_conf = """{{
    "data":[{0}
    ]
}}"""
    conf = ''
    for filename in glob.glob(conf_files):
      data = parseConf(filename).items();
      for key,value in data:
          tmp_conf = getTemplate().format(
              key,
              value[0],
              value[1],
              value[2]
          )
          conf += '%s,' % (tmp_conf)

    if conf[-1] == ',':
        conf=conf[:-1]

    return final_conf.format(conf)


if __name__ == "__main__":

    ret = getPayload()
    sys.exit(ret)
