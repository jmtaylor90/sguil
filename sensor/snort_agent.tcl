#!/usr/bin/env tclsh

# $Id: snort_agent.tcl,v 1.9 2011/02/17 02:55:48 bamm Exp $ #

# Copyright (C) 2002-2013 Robert (Bamm) Visscher <bamm@sguil.net>
#
# This program is distributed under the terms of version 3 of the
# GNU Public License.  See LICENSE for further details.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

#
# Config options in snort_agent.conf.
#

# Don't touch these
set VERSION "SGUIL-0.9.0"
set CONNECTED 0
set PORTSCANFILEWAIT 0
set BYCONNECT 0

proc bgerror { errorMsg } {
                                                                                                                           
    global errorInfo sguildSocketID
                                                                                                                           
    # Catch SSL errors, close the channel, and reconnect.
    # else write the error and exit.
    if { [regexp {^SSL channel "(.*)":} $errorMsg match socketID] } {

        catch { close $sguildSocketID } tmpError
        ConnectToSguilServer

    } else {

        puts "Error: $errorMsg"
        if { [info exists errorInfo] } {
            puts $errorInfo
        }
        exit

    }
                                                                                                                           
}

proc InitBYSocket { port } {

    global DEBUG

    if [catch {socket -server BYConnect -myaddr 127.0.0.1 $port} bySocketID] {
        puts "Error opening socket for barnyard: $bySocketID"
        exit
    }
    if {$DEBUG} { puts "Listening on port $port for barnyard connections." } 

}

proc BYConnect { socketID IPaddr port } {

    global DEBUG BYCONNECT HOSTNAME


    if { $DEBUG } { puts "barnyard connected: $socketID $IPaddr $port" }
    fconfigure $socketID -buffering line -blocking 0 -translation lf
    fileevent $socketID readable [list BYCmdRcvd $socketID]

    #SendToSguild [list SystemMessage "Barnyard connected via sensor localhost."]
    set BYCONNECT 1
    #SendToSguild [list BarnyardInit $HOSTNAME $BYCONNECT]

}

proc BYCmdRcvd { socketID } {

    global DEBUG BYCONNECT

    if { [eof $socketID] || [catch {gets $socketID data} getsError] } {

        if { [info exists getsError] && $DEBUG } { puts "Error: $getsError" }
        catch { close $socketID } closeError
        if { $DEBUG } { puts "BYCmdRcvd: Barnyard disconnected." }
        SendToSguild [list SystemMessage "Barnyard disconnected."]
        SendToSguild [list BarnyardDisConnect [GetCurrentTimeStamp]]
        set BYCONNECT 0

    } else {

        set byCmd [lindex $data 0]

        switch -exact -- $byCmd {
            
            RTEVENT       { BYEventRcvd $socketID [lrange $data 1 end] }
            SidCidRequest { SidCidRequest $socketID }
            default       { puts "Unknown barnyard data: $data" }

        }
    }

}

proc SendToBarnyard { socketID msg } {

    global BYCONNECT DEBUG

    if [catch { puts $socketID $msg } tmpError] {

        catch { close $socketID }
        if { $DEBUG } { puts "SendToBarnyard: Barnyard disconnected." }
        SendToSguild [list SystemMessage "Barnyard disconnected."]
        set BYCONNECT 0
        SendToSguild [list BarnyardDisConnect 0]

    } else {

        catch { flush $socketID }

    }

}

proc SendToSguild { data } {
  global sguildSocketID CONNECTED DEBUG
  if {!$CONNECTED} {
     if {$DEBUG} { puts "Not connected to sguild. Unable to process this request." }
     return 0
  } else {
    if {$DEBUG} {puts "Sending sguild ($sguildSocketID) $data"}
    if [catch { puts $sguildSocketID $data } tmpError ] { puts "ERROR: $tmpError : $data" }
    catch { flush $sguildSocketID }
    return 1
  }
}

proc CleanMsg { msg } {

    regsub -all {\n} $msg {} tmpMsg
    return $tmpMsg

}

proc BYEventRcvd { socketID eventInfo } {

    if { [llength $eventInfo] != 46 } { 
        puts "Bad Event! List length != 46."
        puts $eventInfo
        puts "len = [llength $eventInfo]"
        # We'll do something better when we are out of BETA
        exit 
    }
   
    SendToSguild "BYEventRcvd $socketID $eventInfo"

}

proc SidCidRequest { socketID } {

    global CONNECTED SENSOR_ID

    if { $CONNECTED && [info exists SENSOR_ID] } {

        SendToSguild [list AgentLastCidReq $socketID $SENSOR_ID]

    }
}

proc SendBYLastCid { socketID maxCid } {

    global SENSOR_ID

    SendToBarnyard $socketID [list SidCidResponse $SENSOR_ID $maxCid]
    # Add status updates?

}
proc SendBYConfirmMsg { socketID cid } {

    SendToBarnyard $socketID [list Confirm $cid]

}

proc SendBYFailMsg { socketID cid msg} {

    SendToBarnyard $socketID "Failed to insert $cid: $msg"

}

proc BinCopyToSguild { fileName } {

    global sguildSocketID

    if [ catch {open $fileName r} rFileID ] {

        # Error opening file
      
        puts "ERROR: Opening $fileName: $rFileID"
        catch {close $rFileID} tmpError
        return 0

    }

    fconfigure $rFileID -translation binary
    fconfigure $sguildSocketID -translation binary

    set RETURN 1
    if [ catch {fcopy $rFileID $sguildSocketID} tmpError ] {

        # fcopy failed.
        set RETURN 0
        set CONNECTED 0
        catch { close $sguildSocketID } tmpError
        ConnectToSguilServer

    } else {

        fconfigure $sguildSocketID -encoding utf-8 -translation {auto crlf}

    }

    catch {close $rFileID} tmpError

    return $RETURN

}

proc PingServer {} {

    global CONNECTED PING_DELAY DEBUG

    if {$CONNECTED} { SendToSguild "PING" }

    after $PING_DELAY PingServer

}

# Initialize connection to sguild
proc ConnectToSguilServer {} {

    global sguildSocketID HOSTNAME CONNECTED 
    global SERVER_HOST SERVER_PORT DEBUG BYCONNECT VERSION

    # Connect
    if {[catch {set sguildSocketID [socket $SERVER_HOST $SERVER_PORT]}] > 0} {

        # Connection failed #

        set CONNECTED 0
        if {$DEBUG} {puts "Unable to connect to $SERVER_HOST on port $SERVER_PORT."}
        if {$DEBUG} {puts "Trying again in 15 seconds"}
        after 15000 ConnectToSguilServer

    } else {

        # Connection Successful #

        fconfigure $sguildSocketID -buffering line

        # Version checks
        set tmpVERSION "$VERSION OPENSSL ENABLED"

        if [catch {gets $sguildSocketID} serverVersion] {
            puts "ERROR: $serverVersion"
            catch {close $sguildSocketID}
            exit
         }

        if { $serverVersion == "Connection Refused." } {

            puts $serverVersion
            catch {close $sguildSocketID}
            exit

        } elseif { $serverVersion != $tmpVERSION } {

            catch {close $sguildSocketID}
            puts "Mismatched versions.\nSERVER: ($serverVersion)\nAGENT: ($tmpVERSION)"
            after 15000 ConnectToSguilServer
            return

        }

        if [catch {puts $sguildSocketID [list VersionInfo $tmpVERSION]} tmpError] {
            catch {close $sguildSocketID}
            puts "Unable to send version string: $tmpError"
        }

        catch { flush $sguildSocketID }
        tls::import $sguildSocketID -ssl2 false -ssl3 false -tls1 true

        fileevent $sguildSocketID readable [list SguildCmdRcvd $sguildSocketID]
        set CONNECTED 1
        if {$DEBUG} {puts "Connected to $SERVER_HOST"}
        InitSnortAgent

    }

}

proc InitSnortAgent {} {

    global CONNECTED DEBUG HOSTNAME NET_GROUP

    if {!$CONNECTED} {

       if {$DEBUG} { puts "Not connected to sguild. Sleeping 15 secs." }
       after 15000 InitSnortAgent


    } else {

        SendToSguild [list RegisterAgent snort $HOSTNAME $NET_GROUP]

    }

}

proc RegisterSensorsTypes {} {

    global HOSTNAME BYCONNECT

    # Barnyard
    SendToSguild [list BarnyardInit $HOSTNAME $BYCONNECT]

}

proc SguildCmdRcvd { socketID } {

    global DEBUG SANCPFILEWAIT CONNECTED

    if { [eof $socketID] || [catch {gets $socketID data}] } {

        # Socket closed
        close $socketID
        set CONNECTED 0

        if {$DEBUG} { puts "Socket $socketID closed" }
        if {$DEBUG} { puts "Attempting to reconnect." }

        ConnectToSguilServer

    } else {
        if {$DEBUG} { puts "Sensor Data Rcvd: $data" }
        update

        set sguildCmd [lindex $data 0]

        switch -exact -- $sguildCmd {

            PONG                  { if {$DEBUG} {puts "PONG received"} }
            PING                  { SendToSguild "PONG" }
            AgentInfo             { AgentInfo [lindex $data 1] [lindex $data 2] [lindex $data 3] [lindex $data 4] }
            LastCidResults        { SendBYLastCid [lindex $data 1] [lindex $data 2] }
            Confirm               { SendBYConfirmMsg [lindex $data 1] [lindex $data 2] }
            Failed                { SendBYFailMsg [lindex $data 1] [lindex $data 2] [lindex $data 3] }
            default               { if {$DEBUG} {puts "Sguil Cmd Unkown: $sguildCmd"} }

        }

    }

}

proc DisplayUsage { cmdName } {

    puts "Usage: $cmdName \[-D\] \[-b\] \[-c\] \[-o\] <filename>"
    puts "  -c <filename>: PATH to config (snort_agent.conf) file."
    puts "  -b Port to listen for Barnyard connections on."
    puts "  -D Runs $cmdName in daemon mode."
    exit

}

proc Daemonize {} {

    global PID_FILE DEBUG

    # We need extended tcl to run in the background
    # Load extended tcl
    if [catch {package require Tclx} tclxVersion] {

        puts "ERROR: The tclx extension does NOT appear to be installed on this sysem."
        puts "Extended tcl (tclx) contains the 'fork' function needed to daemonize this"
        puts "process.  Install tclx or background the process manually.  Extended tcl"
        puts "(tclx) is available as a port/package for most linux and BSD systems."
        exit

    }

    set DEBUG 0
    set childPID [fork]
    # Parent exits.
    if { $childPID == 0 } { exit }
    id process group set
    if {[fork]} {exit 0}
    set PID [id process]
    if { ![info exists PID_FILE] } { set PID_FILE "/var/run/snort_agent.pid" }
    set PID_DIR [file dirname $PID_FILE]

    if { ![file exists $PID_DIR] || ![file isdirectory $PID_DIR] || ![file writable $PID_DIR] } {

        puts "ERROR: Directory $PID_DIR does not exists or is not writable."
        puts "Process ID will not be written to file."

    } else {
 
        set pidFileID [open $PID_FILE w]
        puts $pidFileID $PID
        close $pidFileID

    }

}

#
# CheckLineFormat - Parses CONF_FILE lines to make sure they are formatted
#                   correctly (set varName value). Returns 1 if good.
#
proc CheckLineFormat { line } {

    set RETURN 1
    # Right now we just check the length and for "set".
    if { [llength $line] != 3 || [lindex $line 0] != "set" } { set RETURN 0 }
    return $RETURN

}

# May need to add more to this later
proc AgentInfo { sensorName type netName sensorID } {

    global SENSOR_ID

    set SENSOR_ID $sensorID

}

proc GetCurrentTimeStamp {} {

    set timestamp [clock format [clock seconds] -gmt true -f "%Y-%m-%d %T"]
    return $timestamp

}

################### MAIN ###########################

# GetOpts
set state flag

foreach arg $argv {

    switch -- $state {

        flag {

            switch -glob -- $arg {

                --       { set state flag }
                -D       { set DAEMON_CONF_OVERRIDE 1 }
                -c       { set state conf }
                -b       { set state byport } 
                -O       { set state sslpath }
                default  { DisplayUsage $argv0 }

            }

        }

        conf      { set CONF_FILE $arg; set state flag }
        byport    { set BY_PORT $arg; set state flag }
        sslpath   { set TLS_PATH $arg; set state flag }
        default   { DisplayUsage $argv0 }

    }

}

# Parse the config file here
# Default location is /etc/snort_agent.conf or pwd
if { ![info exists CONF_FILE] } {

    # No conf file specified check the defaults
    if { [file exists /etc/snort_agent.conf] } {

        set CONF_FILE /etc/snort_agent.conf

    } elseif { [file exists ./snort_agent.conf] } {

        set CONF_FILE ./snort_agent.conf

    } else {

        puts "Couldn't determine where the snort_agent.tcl config file is"
        puts "Looked for /etc/snort_agent.conf and ./snort_agent.conf."
        DisplayUsage $argv0

    }

}

set i 0
if { [info exists CONF_FILE] } {

    # Parse the config file. Currently the only option is to
    # create a variable using 'set varName value'
    set confFileID [open $CONF_FILE r]
    while { [gets $confFileID line] >= 0 } {

        incr i

        if { ![regexp ^# $line] && ![regexp ^$ $line] } {

            if { [CheckLineFormat $line] } {

                if { [catch {eval $line} evalError] } {
                  puts "Error at line $i in $CONF_FILE: $line"
                  exit
                }

            } else {

                puts "Error at line $i in $CONF_FILE: $line"
                exit

            }

        }

    }

    close $confFileID

} else {

    DisplayUsage $argv0

}

# Command line overrides the conf file.
if {[info exists DAEMON_CONF_OVERRIDE] && $DAEMON_CONF_OVERRIDE} { set DAEMON 1}
if {[info exists DAEMON] && $DAEMON} {Daemonize}

# OpenSSL is required
# Need path?
if { [info exists TLS_PATH] } {

    if [catch {load $TLS_PATH} tlsError] {

        puts "ERROR: Unable to load tls libs ($TLS_PATH): $tlsError"
        DisplayUsage $argv0

    }

}

if { [catch {package require tls} tmpError] }  {

    puts "ERROR: Unable to load tls package: $tmpError"
    DisplayUsage $argv0

}

ConnectToSguilServer
InitBYSocket $BY_PORT
if {$PING_DELAY != 0} { PingServer }
vwait FOREVER
