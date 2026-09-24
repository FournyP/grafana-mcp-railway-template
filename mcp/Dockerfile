# Grafana publishes an official, versioned image for mcp-grafana, so unlike the
# sibling templates there is nothing to build from source here — pin the tag and
# override the entrypoint to translate Railway's environment into CLI flags.
# https://github.com/grafana/mcp-grafana
FROM grafana/mcp-grafana:1.5.1

COPY entrypoint.sh /entrypoint.sh
USER root
RUN chmod +x /entrypoint.sh
USER mcp-grafana

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
