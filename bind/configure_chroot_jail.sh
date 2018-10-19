#!/bin/bash


if [ "$UID" != "0" ] then
    echo "You must run this script as root!"
    exit
fi

#-----------------------------------------------------

#### This is just ripped from http://www.unixwiz.net/techtips/bind9-chroot.html
#### It looks to just create a user and prepare a home directory "jail"

# create initial named user and group

groupadd named
useradd -g named -d /chroot/named -s /bin/true named
passwd -l named  #  "lock" the account

# Remove all the login-related trash under the newly-created home directory

rm -rf /chroot/named

# Re-create the top level jail directory

mkdir -p /chroot/named
cd /chroot/named

# create the hierarchy

mkdir dev
mkdir etc
mkdir logs
mkdir -p var/run
mkdir -p conf/secondaries

# create the devices, but confirm the major/minor device 
# numbers with   "ls -lL /dev/zero /dev/null /dev/random"

mknod dev/null c 1 3
mknod dev/zero c 1 5
mknod dev/random c 1 8

# copy the timezone file

cp /etc/localtime etc

# Create the configuration file.
# This is actively creating a symbolic link to a file that 
# does not exists yet

ln -s /chroot/named/etc/bind/named.conf /etc/named.conf



##########################################
#
# create the BIND configuration file
# THIS WILL NEED TO BE MODIFIED WITH OUR SUBNET
#
# A lot of this modified from here:
# http://www.cymru.com/Documents/secure-bind-template.html
#

cat << EOF >etc/named.conf
// @(#)named.conf 02 OCT 2001 Team Cymru noc@cymru.com 
// Set up our ACLs 
// In BIND 8, ACL names with quotes were treated as different from 
// the same name without quotes. In BIND 9, both are treated as 
// the same. 

acl "xfer" { 
    none;   // Allow no transfers.  If we have other 
            // name servers, place them here.             
};

acl "trusted" {

    // Place our internal and DMZ subnets in here so that 
    // intranet and DMZ clients may send DNS queries.  This 
    // also prevents outside hosts from using our name server 
    // as a resolver for other domains. 
    192.168.1.0/24; 
    localhost;

};

logging {


    channel default_syslog {
        
        // Send most of the named messages to syslog. 
        syslog local2; 
        severity debug;

    }; 

    channel audit_log {
        
        // Send the security related messages to a separate file. 
        file "/var/run/named.log"; 
        severity debug; 
        print-time yes;

    }; 

    category default { default_syslog; }; 
    category general { default_syslog; }; 
    category security { audit_log; default_syslog; }; 
    category config { default_syslog; }; 
    category resolver { audit_log; }; 
    category xfer-in { audit_log; }; 
    category xfer-out { audit_log; }; 
    category notify { audit_log; }; 
    category client { audit_log; }; 
    category network { audit_log; }; 
    category update { audit_log; }; 
    category queries { audit_log; }; 
    category lame-servers { audit_log; };

};


options {
    directory       "/conf";
    pid-file        "/var/run/named.pid";
    statistics-file "/var/run/named.stats";
    memstatistics-file "/var/run/named.memstats";
    dump-file       "/var/run/named.db";
    zone-statistics yes;

    // Prevent DoS attacks by generating bogus zone transfer 
    // requests.  This will result in slower updates to the 
    // slave servers (e.g. they will await the poll interval 
    // before checking for updates). 
    notify no;

    // Generate more efficient zone transfers.  This will place 
    // multiple DNS records in a DNS message, instead of one per 
    // DNS message. 
    transfer-format many-answers;

    // Set the maximum zone transfer time to something more 
    // reasonable.  In this case, we state that any zone transfer 
    // that takes longer than 60 minutes is unlikely to ever 
    // complete.  WARNING:  If you have very large zone files, 
    // adjust this to fit your requirements. 
    max-transfer-time-in 60;

    // We have no dynamic interfaces, so BIND shouldn't need to 
    // poll for interface state {UP|DOWN}. 
    interface-interval 0;


    allow-transfer { 
        // Zone tranfers limited to members of the 
        // "xfer" ACL. 
        xfer; 
    };

    allow-query { 
        // Accept queries from our "trusted" ACL.  We will 
        // allow anyone to query our master zones below. 
        // This prevents us from becoming a free DNS server 
        // to the masses. 
        trusted; 
    };

    allow-query-cache { 
        // Accept queries of our cache from our "trusted" ACL.  
        trusted; 
    };

    # hide our "real" version number
    version         "[secured]";
};


view "internal-in" in { 
    // Our internal (trusted) view. We permit the internal networks 
    // to freely access this view. We perform recursion for our 
    // internal hosts, and retrieve data from the cache for them.

    match-clients { trusted; }; 
    recursion yes; 
    additional-from-auth yes; 
    additional-from-cache yes;

    zone "." in { 
        // Link in the root server hint file. 
        type hint; 
        file "db.root";

        // this is often seen to be "db.root" or "db.rootcache"
        //  or "db.cache" .... use what we have 
    };

    zone "0.0.127.in-addr.arpa" in { 
        // Allow queries for the 127/8 network, but not zone transfers. 
        // Every name server, both slave and master, will be a master 
        // for this zone. 
        type master; 
        file "master/db.127.0.0";

        allow-query { 
            any; 
        };

        allow-transfer { 
            none; 
        }; 
    };

    zone "localhost" {
       type master;
       file "db.localhost";
        allow-query { 
            any; 
        };

        allow-transfer { 
            none;
       };
    };

    zone "internal.example.com" in { 
        // Our internal A RR zone. There may be several of these. 
        type master; 
        file "master/db.internal"; 
    };

    zone "1.168.192.in-addr.arpa" in { 
        // Our internal PTR RR zone. Again, there may be several of these. 
        type master; 
        file "master/db.192.168.1"; 
    };


};


// Create a view for external DNS clients. 
view "external-in" in { 
    // Our external (untrusted) view. We permit any client to access 
    // portions of this view. We do not perform recursion or cache 
    // access for hosts using this view.

    match-clients { any; }; 
    recursion no; 
    additional-from-auth no; 
    additional-from-cache no;

    // Link in our zones 
    zone "." in { 
        type hint; 
        file "db.cache"; 
    };
    zone "example.net" in { 
        type master; 
        file "master/db.example";

        allow-query { 
            any; 
        }; 
    };

    zone "1.1.10.in-addr.arpa" in { 
        type master; 
        file "master/db.10.1.1";

        allow-query { 
            any; 
        }; 
    };
};

// Create a view for all clients perusing the CHAOS class.
// We allow internal hosts to query our version number.
// This is a good idea from a support point of view.
view "external-chaos" chaos { 
    match-clients { any; }; 
    recursion no;

    zone "." { 
        type hint; 
        file "/dev/null"; 
    };

    zone "bind" { 
        type master; 
        file "master/db.bind";

        allow-query { 
            trusted; 
        }; 
        allow-transfer { 
            none; 
        }; 
    };
};



// ------------------------------------------
// --- These are from the first article.


// # The root nameservers
// zone "." {
//     type   hint;
//     file   "db.rootcache";
// };
// 
// # localhost - forward zone
// zone    "localhost" {
//     type    master;
//     file   "db.localhost";
//     notify  no;
// };
// 
// # localhost - inverse zone
// zone    "0.0.127.in-addr.arpa" {
//     type   master;
//     file   "db.127.0.0";
//     notify no;
// };
EOF


## Create the localhost files. These should not have to be touched
cat << EOF >etc/db.localhost
;
; db.localhost
;
$TTL    86400

@       IN SOA   @ root (
                        42              ; serial (d. adams)
                        3H              ; refresh
                        15M             ; retry
                        1W              ; expiry
                        1D )            ; minimum

        IN NS        @
        IN A         127.0.0.1
EOF

cat << EOF > etc/db.bind
;
; @(#)db.bind v1.2 25 JAN 2001 Team Cymru Thomas noc@cymru.com 
; 
$TTL    1D 
$ORIGIN bind. 
@       1D      CHAOS   SOA     localhost. root.localhost. ( 
                2001013101      ; serial 
                3H              ; refresh 
                1H              ; retry 
                1W              ; expiry 
                1D )            ; minimum 
        CHAOS NS        localhost.

version.bind.   CHAOS  TXT "CHAOS records are no fun for Joes." 
authors.bind.   CHAOS  TXT "... or even Pros, for that matter!" 
EOF


## Create the reverse pointer file for localhost.
cat << EOF >etc/db.127.0.0
;
; db.127.0.0
;
$TTL    86400
@       IN      SOA     localhost. root.localhost.  (
                            1 ; Serial
                            28800      ; Refresh
                            14400      ; Retry
                            3600000    ; Expire
                            86400 )    ; Minimum
        IN      NS      localhost.
1       IN      PTR     localhost.
EOF



#### Next we need to generate the RNDC keys.

cd /tmp

key_base=$(dnssec-keygen -r /dev/urandom -a HMAC-MD5 -b 256 -n HOST rndc)

secret_key=$(cat ${key_base}.private | grep "Key:" | cut -d " " -f2)

rm ${key_base}.*


cat << EOF > /chroot/named/etc/rndc.conf
#
# /chroot/named/etc/rndc.conf
#

options {
        default-server  127.0.0.1;
        default-key     "rndckey";
};

server 127.0.0.1 {
        key     "rndckey";
};

key "rndckey" {
        algorithm       "hmac-md5";
        secret          "${secret_key}";
};
EOF



ln -s /chroot/named/etc/rndc.conf /usr/local/etc/rndc.conf
ln -s /chroot/named/etc/rndc.conf /etc/rndc.conf


###### Next manage the permissions!

#
# named.perms
#
#   Set the ownership and permissions on the named directory
#

cd /chroot/named

# By default, root owns everything and only root can write, but dirs
# have to be executable too. Note that some platforms use a dot
# instead of a colon between user/group in the chown parameters}

chown -R root:named .

find . -type f -print | xargs chmod u=rw,og=r     # regular files
find . -type d -print | xargs chmod u=rwx,og=rx   # directories

# the named.conf and rndc.conf must protect their keys
chmod o= etc/*.conf

# the "secondaries" directory is where we park files from
# master nameservers, and named needs to be able to update
# these files and create new ones.

touch conf/secondaries/.empty  # placeholder
find conf/secondaries/ -type f -print | xargs chown named:named
find conf/secondaries/ -type f -print | xargs chmod ug=r,o=

chown root:named conf/secondaries/
chmod ug=rwx,o=  conf/secondaries/

# the var/run business is for the PID file
chown root:root  var/
chmod u=rwx,og=x var/

chown root:named  var/run/
chmod ug=rwx,o=rx var/run/

# named has to be able to create logfiles
chown root:named  logs/
chmod ug=rwx,o=rx logs/

######## Starting the named server.
#
# We should always do this with script. NEVER use just `named`
#
# named.start
#
#       Note: the path given to the "-c" parameter is relative
#       to the jail's root, not the system root.
#
#       Add "-n2" if you have multiple CPUs
#
# usage: named [-c conffile] [-d debuglevel] [-f|-g] [-n number_of_cpus]
#              [-p port] [-s] [-t chrootdir] [-u username]

cd /chroot/named

# make sure the debugging-output file is writable by named
touch named.run
chown named:named named.run
chmod ug=rw,o=r   named.run

PATH=/usr/local/sbin:$PATH named  \
        -t /chroot/named \
        -u named \
        -c /etc/named.conf
