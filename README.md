# MySQL zabbix template
Based on https://share.zabbix.com/databases/mysql/template-mysql-800-items</br>
But I added key mysql.ping and two triggers: mysql is alive and checking if MySQL replication is running

To import template create Value mappings:
<pre>
MySQL - Status
0 ⇒ No
1 ⇒ Yes
</pre></br>
It is possible in zabbix GUI `Administration -> General -> Value mappings -> create Value Map`


On a server that is monitored
place file `check_mysql.pl` in `/etc/zabbix/scripts`
Also place `userparameter_mysql_check.conf` in directory `/etc/zabbix/zabbix_agentd.d/`</br>
Restart the zabbix-agent:
<pre>
systemctl restart zabbix-agent
</pre>
Add Macros in Zabbix Gui for every host after importing the template. Go `Configuration -> Hosts -> Select Host -> Macros`
and create new macros with your own values:
<pre>
{$MYSQL_PWD}
{$MYSQL_USER}
</pre>
Also you can add macro 
`{$DATABASE_NAME}`
to monitor database size

# Zabbix Nginx template

Place the script nginx.sh into /etc/zabbix/scripts, then make it executable:
```bash
# chmod +x /etc/zabbix/scripts/nginx.sh
```
also copy file zabbix_agentd.d/userparameter_nginx.conf
then restart zabbix-agent
```
# systemctl restart zabbix-agent
```

prepare nginx to give statistics
```
server {
    listen 80 default_server;
    server_name _;
    location /status {
    stub_status on;
    access_log off;
    allow 127.0.0.1;
    deny all;
  }
}
```
enable this virtual host:
```bash
# cd /etc/nginx/sites-enabled/
# ln -s ../sites-available/statistics.conf
```
reload the web server:
```
# nginx -t && nginx -s reload
```
install template to show nginx items in zabbix GUI

# Template php-fpm
copy script and userparameter as above
add new location in nginx virtual host `/etc/nginx/sites-available/statistics.conf`
```
location /php-status {
access_log off;
allow 127.0.0.1;
deny all;
include fastcgi_params;
fastcgi_pass unix:/var/run/php5-fpm.socket;
fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
}
```
make sure that statistic is enabled in
```
/etc/php-fpm.d/www.conf
```
uncomment the following:
```
pm.status_path = /php-status
```
restart services:
```
#systemctl restart zabbix-agent
#systemctl restart nginx
#systemctl restart php-fpm
```
