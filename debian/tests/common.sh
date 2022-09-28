# autopkgtest check: helper routines for authdaemond tests
#
# Author: Markus Wanner <markus@bluegap.ch>

TEST_USERS="alice bob carol"

CONFIG_FILES="/etc/courier/authdaemonrc \
	    /etc/courier/authldaprc \
	    /etc/courier/authmysqlrc \
	    /etc/courier/authpgsqlrc \
	    /etc/courier/authsqliterc"

export PGOPTIONS='--client-min-messages=warning'

# exits with code 0 if the given user exists
user_exists() {
    id -u $1 > /dev/null 2>&1
}

# exits with code 0 if the postgresql client tools are installed
has_postgres_client() {
    which psql > /dev/null 2>&1
}

test_authentication() {
    user=$1
    password=$2
    TEST_OUTPUT="$AUTOPKGTEST_ARTIFACTS/testauth-$1.out"
    echo "testing: '$user' with password '$password'"
    /usr/sbin/authtest $user $password > $TEST_OUTPUT
}

authenumerate_as_courier() {
    su -c "/usr/sbin/authenumerate" -s /bin/sh courier
}

# emits a random (512bit, hex encoded) password on stdout
gen_random_password() {
    dd if=/dev/urandom bs=16 count=1 2> /dev/null | hexdump -e '"%x"'
}

# accepts SQL on stdin
postgres_superuser_exec() {
    su postgres -c "psql -X -q -v ON_ERROR_STOP=1 --pset pager=off"
}

create_test_users() {
    echo "== creating test users..."
    for USER in $TEST_USERS; do
        gen_random_password > $USER.password
        useradd --shell /bin/false --password $(cat $USER.password) $USER
    done
}

backup_config_files() {
    echo "== backup config files..."
    for f in $CONFIG_FILES; do
        if [ -f $f ]; then
            cp ${f} ${f}.autopkgtest.bak
        fi
    done
}

restore_config_files() {
    echo "== restore config files..."
    for f in $CONFIG_FILES; do
        if [ -f ${f}.autopkgtest.bak ]; then
            mv ${f}.autopkgtest.bak ${f}
        fi
    done
}

start_authdaemon() {
    echo "== starting authdameon..."
    service courier-authdaemon start
}

start_postgresql() {
    echo "== starting postgresql..."
    service postgresql start
}

# helper methods for dumping test status
dump_file_if_exists() {
    if [ -f $1 ]; then
        echo "===== BEGIN $1 ====="
        cat $1
        echo "===== END $1 ====="
    fi
}

dump_config_files() {
    for f in $CONFIG_FILES; do
        if [ -f ${f}.autopkgtest.bak ]; then
            dump_file_if_exists $f
        fi
    done

    for f in `ls $AUTOPKGTEST_ARTIFACTS/`; do
        dump_file_if_exists $AUTOPKGTEST_ARTIFACTS/$f
    done
}

# cleanup after running tests
finish() {
    echo "== dump..."
    # dump and then restore the config files
    dump_config_files

    echo "== finish..."

    # drop test users
    if user_exists alice; then
        echo "== dropping user alice"
        userdel alice
    fi
    if user_exists bob; then
        echo "== dropping user bob"
        userdel bob
    fi
    if user_exists carol; then
        echo "== dropping user carol"
        userdel carol
    fi

    # restore config files, then restart the authdaemon, so it
    # disconnects from the database. Otherwise authdaemon blocks the
    # database deletion.
    restore_config_files

    # cleanup Postgres databases
    if has_postgres_client; then
        postgres_superuser_exec <<EOSQL
DROP DATABASE IF EXISTS courier_authdaemon_test;
DROP ROLE IF EXISTS courier;
EOSQL
    fi

    for NAME in courier-authdaemon postgresql; do
        if [ -x /etc/init.d/$NAME ]; then
            echo "== stopping service $NAME..."
            service $NAME stop || /bin/true
        fi
    done
}
trap finish EXIT INT QUIT ABRT PIPE TERM
