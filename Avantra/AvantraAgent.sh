#!/bin/bash
#########################################################
# Avantra Agent Installation Script
# NTT MHIS
# Daniel Munoz: daniel.munoz@global.ntt
# Usage: AvantraAgent.sh <user> <password> <option>
# <user>
# User under avantra agent will run. Valid values are xandria or avantra.
# <option>:
# install: install JRE, Agent and configure systemd to start on boot and configure sudoers entries.
# uninstall: will uninstall agent, jre and remove start scripts and sudoers entries.
#  no other parameters are required
# check: will check installation.
#  no password is required
# <password>:
# mandatory, password of avantra os user that will be created. Minimum 8 characters long.
#########################################################
# Defining terminal colors
Cgreen='\e[32m'
Cyellow='\e[43m'
Cred='\e[31m'
Cend='\e[0m'
# Defining some variables
currentdir=$PWD/
usage=$'Usage\nnttAvantraAgent.sh <user> <password> <option>\n<user>\n\t\tUser under avantra agent will run. Valid values are "avantra" or "xandria"\n<option>\n\t\tinstall: install JRE, Agent and configure systemd to start on boot and configure sudoers entries.\n\t\tuninstall: It will remove agent/JRE, systemd scripts end sudoers entries (no user or password required).\n\t\tcheck: will check installation (no user or password required).\n<password>:\n\t\tmandatory, password of avantra os user that will be created. Minimum 8 characters long'

if [ $# -eq 3 ] && [ $3 == "install" ]; then
 if [ $1 != "xandria" ] &&  [ $1 != "avantra" ]; then
  echo "$usage"
  echo ">> Error: user should be avantra or xandria"
  exit 1
 fi
 if [ ${#2} -lt 8 ]; then
  echo "$usage"
  echo ">> Error: Password should be minimun 8 characters long"
  exit 1
 fi
 action="install"
fi
if [ $# -eq 1 ]; then
 if [ $1 == "check" ]; then
  action="check"
 fi
 if [ $1 == "uninstall" ]; then
  action="uninstall"
    fi
fi
if [ -z ${action+x} ]; then
 echo "$usage"
 exit 1
else
 echo "Action:" $action
fi

###############################################################
### START OF CHECK BLOCK
###############################################################
if [ $action == "check" ]; then
 echo ""
 echo ""
 echo "    Checking Avantra Agent Status"
 echo ""
 echo ""
 resultC=`ps -ef|grep xandria_agent|grep -v grep`
 if [ $? -eq 0 ]; then
  echo ">> Agent Process: RUNNING"
  echo "Avantra process user: "ps -ef|grep xandria_agent|grep -v grep |awk '{print $1}'
  echo "Java Running on: "`ps -ef|grep xandria_agent|grep -v grep |awk '{print $8}'`
  echo "Agent directory: "`ps -ef|grep xandria_agent|grep -v grep  |awk '{print $15}' |sed 's/\/lib.*//g'`
 else
  echo ">> Agent process: NOT RUNNING"
 fi
 resuldD=`cat /etc/passwd|egrep 'xandria|avantra'`
 if [ $? -eq 0 ]; then
  echo ">> Agent user in /etc/passwd: FOUND"
  echo "User: "`cat /etc/passwd|egrep 'xandria|avantra'|cut -d':' -f1`
 else
  echo ">> xandria or avantra user on /etc/passwd: NOT FOUND"
 fi
 resultE=`cat /etc/group|cut -d':' -f1|egrep 'xandria|avantra'`
 if [ $? -eq 0 ]; then
  echo ">> xandria/avantra group in /etc/group: FOUND"
  echo "Group: "$resultE
 else
  echo ">> xandria/avantra group in /etc/group: NOT FOUND"
 fi

 sysmanager1=$([[ -L "/sbin/init" ]] && echo 'systemd' || echo 'SysV')
 echo ">> "$sysmanager1 "detected as system manager"
 if [ "$sysmanager1" = "systemd" ]; then
  resultF=`cat /etc/sudoers|egrep -i 'xandria|avantra'`
  if [ $? -eq 0 ]; then
   echo ">> sudoers entries in /etc/sudoers: FOUND"
   echo "entries found:"
   cat /etc/sudoers|egrep -i 'xandria|avantra'
  else
   echo ">> sudoers entries in /etc/sudoers: NOT FOUND"
  fi
  SERVICE_FILE="/etc/systemd/system/avantra-agent.service"
  EXPECTED_PERMS="755"
  read -r -d '' EXPECTED_CONTENT <<'EOF'
[Unit]
Description=Avantra Agent
After=network.target
[Service]
# Or change to the path where the Avantra Agent is installed
ExecStart=/opt/syslink/agent/rc.agent start
# Or change to the path where the Avantra Agent is installed
ExecStop=/opt/syslink/agent/rc.agent stop
# The user running the agent:
User=avantra
Type=forking
# The kill mode must be set to "process" to prevent the automatic
# agent update from being stopped together with the parent
# agent process.
KillMode=process
[Install]
WantedBy=multi-user.target
EOF

  if [ -f "$SERVICE_FILE" ]; then
      ACTUAL_PERMS=$(stat -c "%a" "$SERVICE_FILE")
      if [ "$ACTUAL_PERMS" = "$EXPECTED_PERMS" ]; then
          echo "$SERVICE_FILE has $EXPECTED_PERMS permissions."
      else
          echo "$SERVICE_FILE has $ACTUAL_PERMS permissions (expected $EXPECTED_PERMS)."
      fi

    # Compare contents
      DIFF=$(diff -u <(echo "$EXPECTED_CONTENT") "$SERVICE_FILE")
      if [ -z "$DIFF" ]; then
          echo "$SERVICE_FILE content matches exactly."
      else
          echo "$SERVICE_FILE content does NOT match exactly."
          # Uncomment next line to show the diff
          # echo "$DIFF"
      fi
  else
      echo "$SERVICE_FILE does NOT exist."
  fi
 fi
 if [ "$sysmanager1" = "SysV" ]; then
  resultG=`ls -lad /etc/init.d/rc.agent`
  if [ $? -eq 0 ]; then
   resultH=`ls -lad /etc/init.d/rc.agent |awk '{print $NF}'`
   if [ "$resultH" = "/opt/syslink/agent/rc.agent" ]; then
    echo ">> /etc/init.d/rc.agent link properly pointing to /opt/syslink/agent/rc.agent"
    ls -lad /etc/init.d/rc.agent
    resultI=`chkconfig -l rc.agent |awk '{print $5$6$7}'`
    if [ "$resultI" = "3:on4:on5:on" ]; then
     echo ">> chkconfig check successull:"
     chkconfig -l rc.agent
    fi
   else echo ">> /etc/init.d/rc.agent link  NOT pointing to /opt/syslink/agent/rc.agent"
   fi
  else echo ">> /etc/init.d/rc.agent link NOT FOUND"
  fi
 fi

fi
###############################################################
### END OF CHECK BLOCK
###############################################################

###############################################################
### START OF UNINSTALL BLOCK
###############################################################
if [ $action == "uninstall" ]; then
 read -p "Are you sure you want to uninstall Avantra agent? (y/n)" yn
 if [ "$yn" == "${yn#[Yy]}" ]; then
  echo ">> Exiting..."
  exit 1
 fi
 if [ ! -d /opt/syslink/agent/ ]; then
  echo ">> Avantra /opt/syslink/agent directory not found, exiting..."
  exit 1
 fi
 /opt/syslink/agent/rc.agent stop
  if [ $? -eq 0 ]; then
   echo ">> Agent stopped successfully"
  else
   echo ">> Error stopping Agent..."
  fi
 agentuser=`ls -ld /opt/syslink/agent/ | awk '{print $3}'`
 echo ">> User $agentuser found as agent user"
 userdel -r $agentuser
  if [ $? -eq 0 ]; then
   echo ">> User $agentuser deleted successfully"
  else
   echo ">> Error deleting $agentuser user..."
  fi
 groupdel $agentuser
  if [ $? -eq 0 ]; then
   echo ">> Group $agentuser deleted successfully"
  else
   echo ">> Error deleting $agentuser group..."
  fi
 rm -rf /opt/syslink
  if [ $? -eq 0 ]; then
   echo ">> Directory /opt/syslink deleted successfully"
  else
   echo ">> Error deleting directory /opt/syslink..."
  fi
 rm -rf /home/$agentuser
  if [ $? -eq 0 ]; then
   echo ">> Directory /home/$agentuser deleted successfully"
  else
   echo ">> Error deleting directory /home/$agentuser..."
  fi
 sysmanager=$([[ -L "/sbin/init" ]] && echo 'systemd' || echo 'SysV')
 echo ">> "$sysmanager "detected as system manager"
 if [ "$sysmanager" = "systemd" ]; then
  systemctl disable $agentuser-agent.service
  if [ $? -eq 0 ]; then
   echo ">> systemctl disable $agentuser-agent.service executed successfully"
  else
   echo ">> Error executing systemctl disable $agentuser-agent.service"
  fi
  rm -rf /etc/systemd/system/$agentuser-agent.service
  if [ $? -eq 0 ]; then
   echo ">> File /etc/systemd/system/$agentuser-agent.service deleted successfully"
  else
   echo ">> Error deleting file /etc/systemd/system/$agentuser-agent.service"
  fi
  systemctl daemon-reload
  if [ $? -eq 0 ]; then
   echo ">> systemctl daemon-reload executed successfully"
  else
   echo ">> Error executed systemctl daemon-reload"
  fi
 fi
 if [ "$sysmanager" = "SysV" ]; then
  echo ">> Configure SysV to start agent on boot manually"
 fi
 res=`grep $agentuser /etc/sudoers`
 if [ $? -eq 0 ] && [ ! -f "/etc/sudoers.tmp" ]; then
  touch /etc/sudoers.tmp
  cat /etc/sudoers |grep -v $agentuser > /tmp/sudoers.new
  visudo -c -f /tmp/sudoers.new
  if [ $? -eq 0 ]; then
   cp /tmp/sudoers.new /etc/sudoers
  fi
  rm /etc/sudoers.tmp
  echo ">> Removed $agentuser user from /etc/sudoers"
 else
  echo ">> No $agentuser user entries in /etc/sudoers"
 fi
fi


###############################################################
### END OF UNINSTALL BLOCK
###############################################################

###############################################################
### START OF INSTALL BLOCK
###############################################################

if [ $action == "install" ]; then
 result=`ps -ef|grep xandria_agent|grep -v grep`
 if [ $? -eq 0 ]; then
  echo ">> Agent already running, exiting..."
  echo ">> You can uninstall by executing $0 uninstall"
  echo $result
  exit 1
 fi
 if [ -d /opt/syslink/ ]; then
  echo ">> /opt/syslink/ folder exists, remove agent first..."
  echo ">> You can uninstall by executing $0 uninstall"
  exit 1
 fi
 echo ""
 echo ""
 echo "    Creating User and Directories"
 echo ""
 echo ""
 mkdir /opt/syslink
  if [ $? -eq 0 ]; then
   echo ">> Directory /opt/syslink created successfully"
  else
   echo ">> Error creating directory /opt/syslink... exiting..."
   exit 1
  fi
 groupadd $1 -g 5432
  if [ $? -eq 0 ]; then
   echo ">> Group $1 created successfully"
  else
   echo ">> Error creating group $1... exiting..."
  fi
 ##############################################
 # Discovering if oracle/oinstall groups exist
 ##############################################
 if [ `grep oracle /etc/group` ]; then
  oravar=1;
 fi
 if [ `grep oinstall /etc/group` ]; then
  oinstallvar=1;
 fi
 #####################################################
 # Building useradd command depending on above results
 #####################################################
 if [ ! -z "${oravar+x}" ] && [ ! -z "${oinstallvar+x}" ]; then
  useradd $1 -u 5432 -g $1 -G dba,sapsys,oinstall -p $1 -s /bin/bash
  if [ $? -eq 0 ]; then
   echo ">> Oracle group detected, user created successfully"
  else
   echo ">> Error creating user $1... exiting..."
  fi
 fi
 if [ ! -z "${oravar+x}" ] && [ -z "${oinstallvar+x}" ]; then
  useradd $1 -u 5432 -g $1 -G dba,sapsys -p $1 -s /bin/bash
  if [ $? -eq 0 ]; then
   echo ">> Oracle and oinstall groups detected, user created successfully"
  else
   echo ">> Error creating user $1... exiting..."
  fi
 fi
 if [ -z "${oravar+x}" ] && [ -z "${oinstallvar+x}" ]; then
  useradd $1 -u 5432 -g $1 -G sapsys -p $1 -s /bin/bash
  if [ $? -eq 0 ]; then
   echo ">> User created successfully"
  else
   echo ">> Error creating user $1... exiting..."
  fi
 fi
 mkdir /home/$1
  if [ $? -eq 0 ]; then
   echo ">> Directory /home/$1 created successfully"
  else
   echo ">> Error creating directory /home/$1... exiting..."
  fi
 echo ">> Setting /home/$1 and /opt/syslink permissions"
 chown $1:users /home/$1
 chown $1 /opt/syslink
 cd /opt/syslink
 echo ""
 echo ""
 echo "    Downloading software"
 echo ""
 echo ""
 ##############################################
 # Downloading Avantra Agent from Avantra Server
 # Listing available Agents:
 # curl -s http://xandria-pre.nttcom.ms:9050/AgentUpdate| grep bin |grep -i agent-20 | cut -d '"' -f6 |cut -d '/' -f3|sort -r
 # We will install newest agent
 ##############################################
 echo ">> Available agents in server:"
 curl -s http://xandria-pre.nttcom.ms:9050/AgentUpdate| grep bin |grep -i agent-20 | cut -d '"' -f6 |cut -d '/' -f3|sort -r
 latest=`curl -s http://xandria-pre.nttcom.ms:9050/AgentUpdate|grep bin |grep -i agent-20 | cut -d '"' -f6 |cut -d '/' -f3|sort -r|head -1`
 echo ">> "$latest" will be downloaded"
 wget http://xandria-pre.nttcom.ms:9050/AgentUpdate/$latest
  if [ $? -eq 0 ]; then
   echo ">> Agent software successfully downloaded"
  else
   echo ">> Error downloading agent software... exiting..."
  fi
 ############################################
 # Downloading JRE from Avantra Server
 # Listing available JREs:
 # curl -s http://xandria-pre.nttcom.ms:9050/AgentUpdate| grep jre |grep gz | cut -d '"' -f6 |cut -d '/' -f3|sort -r
 # We will install newest JRE
 ############################################
 echo ">> Available JREs in server:"
 curl -s http://xandria-pre.nttcom.ms:9050/AgentUpdate| grep jre |grep gz | cut -d '"' -f6 |cut -d '/' -f3|sort -r
 latestjre=`curl -s http://xandria-pre.nttcom.ms:9050/AgentUpdate| grep jre |grep gz | cut -d '"' -f6 |cut -d '/' -f3|sort -r|head -1`
 echo ">> "$latestjre" will be downloaded"
 wget http://xandria-pre.nttcom.ms:9050/AgentUpdate/$latestjre
  if [ $? -eq 0 ]; then
   echo ">> JRE downloaded successfully"
  else
   echo ">> Error downloading JRE... exiting..."
  fi
 chmod 777 *
 chown $1 *
 echo ""
 echo ""
 echo "    Installing Agent"
 echo ""
 echo ""
 ##############################################
 # Executing agent installation as $1 user
 ##############################################
 sudo -i -u $1 bash << EOF
 cd /opt/syslink
 tar zxvf jre* > /dev/null 2>&1
 mkdir java
 mv jre* java
 ./agent*bin -- --silent --target-dir=/opt/syslink/agent --jvm=/opt/syslink/java --port=9051 --start=no
EOF
 echo ""
 echo ""
 echo "    Creating startup script"
 echo ""
 echo ""
 #############################################
 # Getting system manager: systemd or sysinitV
 #############################################
 sysmanager=$([[ -L "/sbin/init" ]] && echo 'systemd' || echo 'SysV')
 echo ">> "$sysmanager "detected as system manager"
 if [ "$sysmanager" = "systemd" ];
 then echo "# /etc/systemd/system/$1-agent.service
#
[Unit]
Description=$1 Agent
After=network.target

[Service]
# Or change to the path where the $1 Agent is installed
ExecStart=/opt/syslink/agent/rc.agent start
# Or change to the path where the Avantra Agent is installed
ExecStop=/opt/syslink/agent/rc.agent stop
# The user running the agent:
User=$1
Type=forking
# The kill mode must be set to "process" to prevent the automatic
# agent update from being stopped together with the parent
# agent process.
KillMode=process

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/$1-agent.service
 chmod 755 /etc/systemd/system/$1-agent.service
 systemctl enable $1-agent.service
 systemctl daemon-reload

 fi
 #############################################
 # Adding entries to /etc/sudoers
 #############################################
 echo ">> Adding $1 user to /etc/sudoers"
 if [ ! -f "/etc/sudoers.tmp" ]; then
 touch /etc/sudoers.tmp
 cat /etc/sudoers > /tmp/sudoers.new
 echo "$1 ALL=NOPASSWD:/usr/bin/systemctl start $1-agent
$1 ALL=NOPASSWD:/usr/bin/systemctl stop $1-agent
$1 ALL=NOPASSWD:/usr/bin/systemctl restart $1-agent" >>  /tmp/sudoers.new
 visudo -c -f /tmp/sudoers.new
 if [ "$?" -eq "0" ]; then
  cp /tmp/sudoers.new /etc/sudoers
 fi
 rm /etc/sudoers.tmp
 echo ">> Added $1 user to /etc/sudoers"
 else
  echo ">> Error, can't add entries in /etc/sudoers since /etc/sudoers.tmp exists. Do it manually."
 fi

 sudo -i -u $1 bash << EOF
 echo ">> Starting agent as $1 user"
 echo "sudo systemctl start $1-agent"
 sudo systemctl start $1-agent
EOF

 rm /opt/syslink/agent*bin

 echo ""
 echo ""
 echo "    Completed, checking agent status"
 echo ""
 echo ""
 /opt/syslink/agent/rc.agent status

fi
###############################################################
### END OF INSTALL BLOCK
###############################################################