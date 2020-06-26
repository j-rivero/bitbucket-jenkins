if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <json_file> <new_pr|pr_update>"
    exit 1
fi

case ${2} in
   'new_pr')
      event_hdr='pullrequest:created'
      ;;
    'pr_update')
      event_hdr="pullrequest:updated"
      ;;
    *)
      echo "Unkown action ${2}"
      exit 1
esac


curl -X POST \
    -H "Content-Type: application/json" \
    -H "x-event-key: ${event_hdr}" \
    -d @${1} http://localhost:9999
