// Railway Infrastructure as Code: railway config plan | apply
//
// An apply deletes every resource this file does not declare, so link it to a
// project dedicated to this template.
//
// Secrets stay out of here. Export them for the first apply; later runs omit
// them and preserve() keeps what Railway holds.
//
//   export API_KEYS=$(openssl rand -hex 32)
//   export GRAFANA_URL=http://grafana.railway.internal:3000
//   export GRAFANA_SERVICE_ACCOUNT_TOKEN=glsa_...

import { defineRailway, github, preserve, project, service } from "railway/iac";

const REPO = "FournyP/grafana-mcp-railway-template";

// Matched by name, so keep these identical to Railway: a mismatch is a
// delete and recreate, not a rename.
const GATEWAY_SERVICE = "grafana-mcp-gateway";
const MCP_SERVICE = "grafana-mcp";

// The gateway needs this as a literal for its upstream URL and Host rewrite.
const MCP_PORT = "8000";

/** Push the value from the local environment if present, else keep Railway's. */
const fromEnvOrPreserve = (name: string) => process.env[name] ?? preserve();

export default defineRailway(() => {
  // No domain here: auth lives in the gateway, and this service has none.
  const mcp = service(MCP_SERVICE, {
    // Each service builds from its own directory; there is no root Dockerfile.
    source: github(REPO, { branch: "main", rootDirectory: "mcp" }),
    build: { builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    env: {
      // The port the upstream binds. Pinned rather than left to Railway, so the
      // gateway's MCP_PORT literal below cannot drift from it.
      PORT: "8000",

      // On Railway: http://<grafana-service>.railway.internal:<port>
      GRAFANA_URL: fromEnvOrPreserve("GRAFANA_URL"),

      // Set the token, or both username and password. All three are preserved:
      // an apply that dropped them would leave the server unable to start.
      GRAFANA_SERVICE_ACCOUNT_TOKEN: fromEnvOrPreserve("GRAFANA_SERVICE_ACCOUNT_TOKEN"),
      GRAFANA_USERNAME: fromEnvOrPreserve("GRAFANA_USERNAME"),
      GRAFANA_PASSWORD: fromEnvOrPreserve("GRAFANA_PASSWORD"),

      // The second auth layer, paired with the gateway's MCP_SERVER_TOKEN.
      MCP_GRAFANA_SERVER_TOKEN: fromEnvOrPreserve("MCP_GRAFANA_SERVER_TOKEN"),

      // Comma-separated tool allowlist, e.g. loki,prometheus. Empty means all.
      ENABLED_TOOLS: fromEnvOrPreserve("ENABLED_TOOLS"),

      // restricted passes --disable-write: a leaked key cannot mutate anything.
      ACCESS_MODE: process.env.ACCESS_MODE ?? "restricted",
      LOG_LEVEL: "info",
    },
  });

  const gateway = service(GATEWAY_SERVICE, {
    source: github(REPO, { branch: "main", rootDirectory: "gateway" }),
    build: { builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    deploy: {
      // Answered by nginx, so it stays green while the mcp service restarts.
      healthcheckPath: "/health",
    },
    env: {
      // nginx listens here. Pinned so the domain's target port and the port
      // Railway dials cannot disagree, which reads as "connection refused".
      PORT: "80",

      // Comma-separated bearer tokens. Per key: A-Z a-z 0-9 . _ ~ + / = -
      API_KEYS: fromEnvOrPreserve("API_KEYS"),

      MCP_HOST: mcp.env.RAILWAY_PRIVATE_DOMAIN,
      MCP_PORT,

      // Credential the gateway presents upstream; must equal the mcp service's
      // MCP_GRAFANA_SERVER_TOKEN.
      MCP_SERVER_TOKEN: fromEnvOrPreserve("MCP_SERVER_TOKEN"),

      // true also accepts /k/<key>/mcp, for clients that cannot send a header.
      PATH_KEY_AUTH: process.env.PATH_KEY_AUTH ?? "false",
    },
  });

  return project("Grafana MCP", { resources: [mcp, gateway] });
});
