#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"

# required to make utils.sh script being able to work, do not remove:
# ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.cdb-table.yml"
log "Starting up oracle container to get generated cert from oracle server wallet"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.cdb-table-mtls.yml" up -d oracle

# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Completed: ALTER DATABASE OPEN" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"
log "Setting up Oracle Database Prerequisites"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA
     CREATE ROLE C##CDC_PRIVS;
     GRANT CREATE SESSION TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR TO C##CDC_PRIVS;
     GRANT LOGMINING TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOGMNR_CONTENTS TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$DATABASE TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$THREAD TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$PARAMETER TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$NLS_PARAMETERS TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$TIMEZONE_NAMES TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_INDEXES TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_OBJECTS TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_USERS TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_CATALOG TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_CONSTRAINTS TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_CONS_COLUMNS TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_TAB_COLS TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_IND_COLUMNS TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_ENCRYPTED_COLUMNS TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_LOG_GROUPS TO C##CDC_PRIVS;
     GRANT SELECT ON ALL_TAB_PARTITIONS TO C##CDC_PRIVS;
     GRANT SELECT ON SYS.DBA_REGISTRY TO C##CDC_PRIVS;
     GRANT SELECT ON SYS.OBJ\$ TO C##CDC_PRIVS;
     GRANT SELECT ON DBA_TABLESPACES TO C##CDC_PRIVS;
     GRANT SELECT ON DBA_OBJECTS TO C##CDC_PRIVS;
     GRANT SELECT ON SYS.ENC\$ TO C##CDC_PRIVS;
     GRANT SELECT ANY TABLE TO C##CDC_PRIVS;

     -- Following privileges are required additionally for 19c compared to 12c.
     GRANT SELECT ON V_\$ARCHIVED_LOG TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOG TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOGFILE TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$INSTANCE to C##CDC_PRIVS;

     CREATE USER C##MYUSER IDENTIFIED BY mypassword DEFAULT TABLESPACE USERS;
     ALTER USER C##MYUSER QUOTA UNLIMITED ON USERS;

     GRANT C##CDC_PRIVS to C##MYUSER;

     GRANT CREATE TABLE TO C##MYUSER container=all;
     GRANT CREATE SEQUENCE TO C##MYUSER container=all;
     GRANT CREATE TRIGGER TO C##MYUSER container=all;
     GRANT FLASHBACK ANY TABLE TO C##MYUSER container=all;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_D TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_LOGREP_DICT TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_SESSION TO C##CDC_PRIVS;
     
     -- Enable Supplemental Logging for All Columns
     ALTER SESSION SET CONTAINER=cdb\$root;
     ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
     ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
     exit;
EOF

log "Inserting initial data"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF

     create table CUSTOMERS (
          id NUMBER(10) GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH 42) NOT NULL PRIMARY KEY,
          first_name VARCHAR(50),
          last_name VARCHAR(50),
          email VARCHAR(50),
          gender VARCHAR(50),
          club_status VARCHAR(20),
          comments VARCHAR(90),
          create_ts timestamp DEFAULT CURRENT_TIMESTAMP ,
          update_ts timestamp
     );

     CREATE OR REPLACE TRIGGER TRG_CUSTOMERS_UPD
     BEFORE INSERT OR UPDATE ON CUSTOMERS
     REFERENCING NEW AS NEW_ROW
     FOR EACH ROW
     BEGIN
     SELECT SYSDATE
          INTO :NEW_ROW.UPDATE_TS
          FROM DUAL;
     END;
     /

     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (2, 'Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (3, 'Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (4, 'Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (5, 'Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach');
     exit;
EOF

log "Setting up SSL on oracle server..."
# https://www.oracle.com/technetwork/topics/wp-oracle-jdbc-thin-ssl-130128.pdf
log "Create a wallet for the test CA"

docker exec oracle bash -c "orapki wallet create -wallet /tmp/root -pwd WalletPasswd123"
# Add a self-signed certificate to the wallet
docker exec oracle bash -c "orapki wallet add -wallet /tmp/root -dn CN=root_test,C=US -keysize 2048 -self_signed -validity 3650 -pwd WalletPasswd123"
# Export the certificate
docker exec oracle bash -c "orapki wallet export -wallet /tmp/root -dn CN=root_test,C=US -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123"

log "Create a wallet for the Oracle server"

# Create an empty wallet with auto login enabled
docker exec oracle bash -c "orapki wallet create -wallet /tmp/server -pwd WalletPasswd123 -auto_login"
# Add a user In the wallet (a new pair of private/public keys is created)
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -keysize 2048"
# Export the certificate request to a file
docker exec oracle bash -c "orapki wallet export -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -request /tmp/server/creq.txt"
# Using the test CA, sign the certificate request
docker exec oracle bash -c "orapki cert create -wallet /tmp/root -request /tmp/server/creq.txt -cert /tmp/server/cert.txt -validity 3650 -pwd WalletPasswd123"
log "You now have the following files under the /tmp/server directory"
docker exec oracle ls /tmp/server
# View the signed certificate:
docker exec oracle bash -c "orapki cert display -cert /tmp/server/cert.txt -complete"
# Add the test CA's trusted certificate to the wallet
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -trusted_cert -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123"
# add the user certificate to the wallet:
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -user_cert -cert /tmp/server/cert.txt -pwd WalletPasswd123"

cd ${DIR}/mtls
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
log "Create a JKS keystore"
# Create a new private/public key pair for 'CN=connect,C=US'
rm -f keystore.jks
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -genkey -alias testclient -dname 'CN=connect,C=US' -storepass 'welcome123' -storetype JKS -keystore /tmp/keystore.jks -keyalg RSA

# Generate a CSR (Certificate Signing Request):
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -certreq -alias testclient -file /tmp/csr.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
# Sign the client certificate using the test CA (root)
docker cp csr.txt oracle:/tmp/csr.txt
docker exec oracle bash -c "orapki cert create -wallet /tmp/root -request /tmp/csr.txt -cert /tmp/cert.txt -validity 3650 -pwd WalletPasswd123"
# import the test CA's certificate:
docker cp oracle:/tmp/root/b64certificate.txt b64certificate.txt
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -noprompt -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
# Import the signed certificate
docker cp oracle:/tmp/cert.txt cert.txt
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -alias testclient -file /tmp/cert.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
log "Displaying keystore"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -list -keystore /tmp/keystore.jks -storepass 'welcome123' -v

log "Create a JKS truststore"
rm -f truststore.jks
# We import the test CA certificate
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/truststore.jks -storetype JKS -storepass 'welcome123' -noprompt
log "Displaying truststore"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -list -keystore /tmp/truststore.jks -storepass 'welcome123' -v

cd ${DIR}

log "Update listener.ora, sqlnet.ora and tnsnames.ora"
docker cp ${PWD}/mtls/listener.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/listener.ora
docker cp ${PWD}/mtls/sqlnet.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/sqlnet.ora
docker cp ${PWD}/mtls/tnsnames.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/tnsnames.ora

docker exec -i oracle lsnrctl << EOF
reload
stop
start
EOF

log "Sleeping 60 seconds"
sleep 60

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.cdb-table-mtls.yml" up -d

../../scripts/wait-for-connect-and-controlcenter.sh

log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":1,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1532,
               "oracle.sid": "ORCLCDB",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "oracle.ssl.truststore.file": "/tmp/truststore.jks",
               "oracle.ssl.truststore.password": "welcome123",
               "oracle.connection.javax.net.ssl.keyStore": "/tmp/keystore.jks",
               "oracle.connection.javax.net.ssl.keyStorePassword": "welcome123",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto",
               "topic.creation.redo.include": "redo-log-topic",
               "topic.creation.redo.replication.factor": 1,
               "topic.creation.redo.partitions": 1,
               "topic.creation.redo.cleanup.policy": "delete",
               "topic.creation.redo.retention.ms": 1209600000,
               "topic.creation.default.replication.factor": 1,
               "topic.creation.default.partitions": 1,
               "topic.creation.default.cleanup.policy": "delete"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .

log "Waiting 20s for connector to read existing data"
sleep 20

log "Running SQL scripts"
for script in ../../connect/connect-cdc-oracle19-source/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

log "Waiting 20s for connector to read new data"
sleep 20

log "Verifying topic ORCLCDB.C__MYUSER.CUSTOMERS: there should be 13 records"
set +e
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLCDB.C__MYUSER.CUSTOMERS --from-beginning --max-messages 13 > /tmp/result.log  2>&1
set -e
cat /tmp/result.log
log "Check there is 5 snapshots events"
if [ $(grep -c "op_type\":{\"string\":\"R\"}" /tmp/result.log) -ne 5 ]
then
     logerror "Did not get expected results"
     exit 1
fi
log "Check there is 3 insert events"
if [ $(grep -c "op_type\":{\"string\":\"I\"}" /tmp/result.log) -ne 3 ]
then
     logerror "Did not get expected results"
     exit 1
fi
log "Check there is 4 update events"
if [ $(grep -c "op_type\":{\"string\":\"U\"}" /tmp/result.log) -ne 4 ]
then
     logerror "Did not get expected results"
     exit 1
fi
log "Check there is 1 delete events"
if [ $(grep -c "op_type\":{\"string\":\"D\"}" /tmp/result.log) -ne 1 ]
then
     logerror "Did not get expected results"
     exit 1
fi

log "Verifying topic redo-log-topic: there should be 9 records"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning --max-messages 9

log "🚚 If you're planning to inject more data, have a look at https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-cdc-oracle19-source/README.md#note-on-redologrowfetchsize"
