#!/bin/bash
################################################# 第一部分 ###############################################
#1.判断系统版本
version=$(egrep -o "el[6-9]|fc2[2-9]|ubuntu" /proc/version)

if [ $(egrep -c -o "el[6-9]|fc2[2-9]|ubuntu" /proc/version) -eq 0 ]; then
    printf "\e[42m\e[31mError: Your OS is NOT CentOS or RHEL or Fedora and Ubuntu.\e[0m\n"
    exit 1
fi

if [ "$version" = "ubuntu" ]; then
	install="sudo apt-get -y install"
elif [ "$version" = "fc2*" ]; then
	install="dnf -y install"
else
	install="yum -y install"
fi


#2.安装expect
if [ "$(ls /usr/bin/ |egrep -c '^at$|^crontab$|^scp$|^expect$')"  -ne 4 ]; then
	$install expect at cronie openssh-clients
fi

if [ ! -f ./hosts.txt ]; then
	echo -e "You must first Add hosts.txt, Format: \"MARK:USER:IP:PORT:PASS\"\nExample: echo 'node5:root:10.0.0.5:22:password' >>./hosts.txt"
	exit 0
fi

################################################# 第二部分 ###############################################
#MARK:USER:IP:PORT:PASS

SSH() {
sed -i '/expect.sh SSH/d' /var/spool/cron/$(users) 2>/dev/null

#3.生成密钥对
expect -c "
set timeout 60
spawn ssh-keygen -t rsa
expect {   
                \"Enter file in which to save the key *\" {send \"\r\"; exp_continue}
                \"*y/n*\" {send \"y\r\"; exp_continue}
                \"*passphrase*\" {send \"\r\"; exp_continue}
                \"*passphrase*\" {send \"\r\";}
}
"


for i in $(cat /tmp/hosts.txt); do
	IP=$(echo "$i"|cut -f3 -d":")
	PORT=$(echo "$i"|cut -f4 -d":")
	USER=$(echo "$i"|cut -f2 -d":")
	PASS=$(echo "$i"|cut -f5 -d":")
	if [ -z "$USER" ]; then USER=root; fi
	if [ -z "$PORT" ]; then PORT=22; fi
	
	if [ -z "$(ip addr |grep $IP)" ]; then
		#4.批量ssh认证建立
		expect -c "
		set timeout 60
		spawn ssh-copy-id -p $PORT $USER@$IP
		expect {
                \"*yes/no*\" {send \"yes\r\"; exp_continue}
                \"*password*\" {send \"$PASS\r\"; exp_continue}
		}
		"
	fi
done
}


SSHALL() {
for i in $(cat /tmp/hosts.txt); do
	IP=$(echo "$i"|cut -f3 -d":")
	PORT=$(echo "$i"|cut -f4 -d":")
	USER=$(echo "$i"|cut -f2 -d":")
	if [ -z "$USER" ]; then USER=root; fi
	if [ -z "$PORT" ]; then PORT=22; fi

	if [ -z "$(ip addr |grep $IP)" ]; then
		#5.添加所有主机相互认证
		scp -P $PORT $0 $USER@$IP:~/expect.sh
		scp -P $PORT ./hosts.txt $USER@$IP:~

		#ssh -p $PORT $USER@$IP "nohup /bin/sh ~/expect.sh SSH &"                        #这一条会在当前窗口执行完所有
		ssh -p $PORT $USER@$IP '[ -z "$(ps -ef |grep crond |grep -v grep)" ] && crond'   #启动CROND
		ssh -p $PORT $USER@$IP "echo '* * * * * . /etc/profile;/bin/sh ~/expect.sh SSH' >>/var/spool/cron/$USER"  #默认mini安装的centos、fedora都没有expect、at命令
		#ssh -p $PORT $USER@$IP '[ -z "$(ps -ef |grep crond |grep -v grep)" ] && atd'    #启动ATD
		#ssh -p $PORT $USER@$IP "echo '/bin/sh ~/expect.sh SSH' |at now + 1 minutes"     #用这一条要小心了，如果脚本参数是SSHALL，将会进入死循环，你只有将at包卸载才能停止

		#ssh -p $PORT $USER@$IP "sed -i '/expect.sh SSH/d' /var/spool/cron/$USER"
		#ssh -p $PORT $USER@$IP "rpm -e expect at && rm -f ~/.ssh/*"
	fi
done
}


SCP() {
for i in $(cat /tmp/hosts.txt); do
	IP=$(echo "$i"|cut -f3 -d":")
	PORT=$(echo "$i"|cut -f4 -d":")
	if [ -z "$USER" ]; then USER=root; fi
	if [ -z "$PORT" ]; then PORT=22; fi
	
	if [ -z "$(ip addr |grep $IP)" ]; then
		echo "------------> $IP <-------------------"
		scp -rpC -P $PORT $FILE $USER@$IP:~
		echo
	fi
done
}


PCS() {
for i in $(cat /tmp/hosts.txt); do
	IP=$(echo "$i"|cut -f3 -d":")
	PORT=$(echo "$i"|cut -f4 -d":")
	if [ -z "$USER" ]; then USER=root; fi
	if [ -z "$PORT" ]; then PORT=22; fi
	
	if [ -z "$(ip addr |grep $IP)" ]; then
		echo "------------> $IP <-------------------"
		scp -rpC -P $PORT $USER@$IP:$FILE ~
		echo
	fi
done
}


COMM() {
for i in $(cat /tmp/hosts.txt); do
	IP=$(echo "$i"|cut -f3 -d":")
	PORT=$(echo "$i"|cut -f4 -d":")
	if [ -z "$USER" ]; then USER=root; fi
	if [ -z "$PORT" ]; then PORT=22; fi
	
	if [ -z "$(ip addr |grep $IP)" ]; then
		echo "------------> $IP <-------------------"
		ssh -p $PORT $USER@$IP "$CMD"
		echo
	fi
done
}


PKGS() {
for i in $(cat /tmp/hosts.txt); do
	IP=$(echo "$i"|cut -f3 -d":")
	PORT=$(echo "$i"|cut -f4 -d":")
	if [ -z "$USER" ]; then USER=root; fi
	if [ -z "$PORT" ]; then PORT=22; fi
	
	if [ -z "$(ip addr |grep $IP)" ]; then
		echo "------------> $IP <-------------------"
		version="$(ssh $USER@$IP 'egrep -o "el[6-9]|fc2[2-9]|ubuntu" /proc/version')"
		pkgs="$(ssh -p $PORT $USER@$IP "if [ "$version" = "ubuntu" ]; then echo 'sudo apt-get'; elif [ "$version" = "fc2*" ]; then echo 'dnf'; else echo 'yum'; fi")"
		ssh -p $PORT $USER@$IP "$pkgs $CMD"
		echo
	fi
done
}


CLEAN() {
for i in $(cat /tmp/hosts.txt); do
	IP=$(echo "$i"|cut -f3 -d":")
	PORT=$(echo "$i"|cut -f4 -d":")
	USER=$(echo "$i"|cut -f2 -d":")
	PASS=$(echo "$i"|cut -f5 -d":")
	if [ -z "$USER" ]; then USER=root; fi
	if [ -z "$PORT" ]; then PORT=22; fi

	expect -c "
	set timeout 60
	spawn ssh -p $PORT $USER@$IP
	expect {
                \"*yes/no*\" {send \"yes\r\"; exp_continue}
                \"*password*\" {send \"$PASS\r\"; exp_continue}
                \"*# *\" {send \"rm -f ~/.ssh/* && exit \r\"; exp_continue}
	}
	"
done
}


################################################# 第三部分 ###############################################

if [ "${1:0:2}" == '-m' ]; then
	awk -F: '{if($1~/'${2:0:99}'/) print}' ./hosts.txt >/tmp/hosts.txt
	ACMD="$3"
	CMD=$4
	FILE=$4
else
	cat ./hosts.txt >/tmp/hosts.txt
	ACMD="$1"
	CMD=$2
	FILE=$2
fi


#脚本控制程序

case $ACMD in
    SSH)
            SSH
    ;;

    SSHALL)
            SSHALL
    ;;

    COMM)
            COMM
    ;;

    PKGS)
            PKGS
    ;;

    SCP)
            SCP
    ;;

    PCS)
            PCS
    ;;

    CLEAN)
            CLEAN
    ;;

       *)   echo -e "Usage: 
	    File hosts.txt Format: \"MARK:USER:IP:PORT:PASS\". example: echo 'node5:root:10.0.0.5:22:password' >>./hosts.txt
	    You must first Establish SSH Trust: $0 SSH \nExample: 
	    SSH Trust: $0 SSH
	    ALL SSH Trust: $0 SSHALL
	    RUN Command: $0 [-m mark] COMM <'ls && crond'>
	    Package management: $0 [-m mark] PKGS <'install openssh-clients -y'>
	    SCP copy local file to remote user home: $0 [-m mark] SCP <file.txt>
	    PCS copy remote file to local user home: $0 [-m mark] PCS <file.txt>
	    Clean SSH key: $0 [-m mark] CLEAN
	    MARK: -m '^nodeN$'"
    ;;
esac
