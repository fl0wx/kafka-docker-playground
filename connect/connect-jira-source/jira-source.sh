#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh



JIRA_URL=${JIRA_URL:-$1}
JIRA_USERNAME=${JIRA_USERNAME:-$2}
JIRA_API_TOKEN=${JIRA_API_TOKEN:-$3}

if [ -z "$JIRA_URL" ]
then
     logerror "JIRA_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$JIRA_USERNAME" ]
then
     logerror "JIRA_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$JIRA_API_TOKEN" ]
then
     logerror "JIRA_API_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# take since last 6 months
#SINCE=$(date -v-4320H "+%Y-%m-%d %H:%M")
SINCE="2021-01-01 00:00"

# log "Enable debug logging"
# curl -X PUT \
#      -H "Content-Type: application/json" \
#      -d '{"level": "DEBUG"}' \
#      http://localhost:8083/admin/loggers/org.apache.http.wire | jq .

log "Creating Jira Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.jira.JiraSourceConnector",
                    "topic.name.pattern":"jira-topic-${resourceName}",
                    "tasks.max": "1",
                    "jira.url": "'"$JIRA_URL"'",
                    "jira.since": "'"$SINCE"'",
                    "jira.username": "'"$JIRA_USERNAME"'",
                    "jira.api.token": "'"$JIRA_API_TOKEN"'",
                    "jira.tables": "issues",
                    "jira.resources": "issues",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jira-source/config | jq .


sleep 10

log "Verify we have received the data in jira-topic-issues topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic jira-topic-issues --from-beginning --property print.key=true --max-messages 1
