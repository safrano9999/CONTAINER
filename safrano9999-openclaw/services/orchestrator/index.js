import { spawn } from "node:child_process";
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

const JOB_PREFIX = "safrano9999-routines-";
const RUNNER = process.env.SAFRANO9999_ROUTINES_BIN ?? "/usr/local/bin/safrano9999-routines";

function isManagedCronEvent(event) {
  return event?.action === "started"
    && typeof event.jobId === "string"
    && event.jobId.startsWith(JOB_PREFIX);
}

export default definePluginEntry({
  id: "safrano9999-routines-orchestrator",
  name: "SAFRANO9999 Routines Orchestrator",
  description: "Container-only hook that maps OpenClaw cron events to the routines script.",
  register(api) {
    api.on("cron_changed", async (event) => {
      if (!isManagedCronEvent(event)) {
        return;
      }
      spawn(RUNNER, [], { env: { ...process.env }, stdio: "inherit" });
    }, { priority: 0, timeoutMs: 1000 });
  },
});
