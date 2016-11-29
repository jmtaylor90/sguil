# Sguil
Sguil (pronounced sgweel) is built by network security analysts for network security analysts. Sguil's main component is an intuitive GUI that provides access to realtime events, session data, and raw packet captures. Sguil facilitates the practice of Network Security Monitoring and event driven analysis. The Sguil client is written in tcl/tk and can be run on any operating system that supports tcl/tk (including Linux, BSD, Solaris, MacOS, and Win32).

## Source Code Layout
Files are located in the directory named for where they will be installed.

## Client
- `sguil.tk`: Analysis GUI client and its config (`squil.conf`) file.
- `lib`: contains some tcl scripts that are needed by the client.

## Sensor
- `snort_agent.tcl` --  a script that runs on the sensor that takes input from barnyard and sends alerts to the `sguild` server.  It also loads portscan, session, and sensor statistics to the `sguild` server.
- `pcap_agent.tcl` --  a script that runs on the sensor and processes requests for packet data from `sguild`.
- `./contrib` -- some stuff someone gave us... don't ask me how to use it.

## server -- Contains
- `sguild`: The Sguil Server (again a TCL script) and its conf file.  This is the brains behind this whole mess. This stuff gets installed on the database server.  
- `sguild.queries`: Configuration file for standard queries.
- `sguild.access`: Configuration file for user access control.
- `sguild.email`: Configuration file for automatic email alerts from `sguild`.
- `sql_scripts`: Scripts to create the sguildb database structure.

## `./doc`
A bunch of (hopefully) helpful documents.

## `./contrib`
Some more stuff, ya got me.

## Architecture
- Server (`sguild`) receives commands from the client, and makes requests to the sensors.
- Client (`sguil.tk`) is used by analysts; they connect directly to the server.
- Sensors (`pcap_agent.tcl`, `sensor_agent.tcl`, `snort_agent.tcl`) receive commands from the server.

### Developer view
If you want to understand the Architecture in depth from a development point of view, read the source of the below files. First, get up to speed with [Tcl syntax](https://www.tcl.tk/about/language.html).
- `sensor/pcap_agent.tcl` and then search for `SendToSguild`, read over `proc SguildCmdRcvd`, read over `proc SendToSguild`.
- `server/lib/SguildClientCmdRcvd.tcl` is the source for when a command is received from the client. Read over `proc ClientCmdRcvd`.
- `server/lib/SguildSensorCmdRcvd.tcl` is the source for when a command is received from a sensor. Read over `proc SensorCmdRcvd`.

## Setup
### `sguild`
1. Clone this source to target server.
2. Install MySQL/Percona/MariaDB.
3. Create a database for sguild as well as a user and password; for example:
```
create database sguild;
create user 'sguildb'@'localhost' identified by 'sguildb';
grant all on sguildb.* to `sguildb`@'localhost';
create user 'sguildb'@'%' identified by 'sguildb';
grant all on sguildb.* to `sguildb`@'%';
flush privileges;
```
4. Initialize the database: `mysql -u sguildb -p sguildb < sguil/server/sql_scripts/create_sguildb.sql`
5. Edit `sguild.conf`; set `DBNAME`, `DBPASS`, `DBHOST`, `DBPORT`, and `DBUSER`.
6. Enable EPEL repository; `yum localinstall https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm`
7. Install dependencies: `yum install tcl tcl-mysqltcl tclx tcllib tcltls`
8. Create SSL certs and path:
    - `mkdir -p /etc/sguild/certs`
    - `openssl genrsa -out sguild.key 4096` and copy it to the above directory.
    - Create a self signed cert based on above key, name it `sguild.pem` and copy it to the directory.
9. Add a user: `tclsh sguild -c sguild.conf -adduser <name>`
10. Start `sguild`: `tclsh sguild -c sguild.conf`
11. Start `xscriptd` (after starting sguild); this allows for TLS communication: `tclsh xscriptd -C /etc/sguild/certs/ -o`
12. Attempt to connect the server with the client: `tclsh sguil.tk`

## License
Copyright (C) 2002-2014 Robert (Bamm) Visscher <bamm@sguil.net>

GPLv3 - See LICENSE file for more details
